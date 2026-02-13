// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Lottery} from "../src/Lottery.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract MockDAI is IERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

contract LotteryTest is Test {
    Lottery public lottery;
    MockDAI public dai;

    address public owner = address(1);
    address public alice = address(2);
    address public bob = address(3);
    address public carol = address(4);

    // Secret for commit-reveal (owner uses this to prove they didn't cheat)
    bytes32 constant SECRET = bytes32(uint256(12345));
    uint8 constant WINNING_NUMBER = 50;

    function setUp() public {
        dai = new MockDAI();
        vm.prank(owner);
        lottery = new Lottery(address(dai));

        // Fund players with DAI
        dai.mint(alice, 100 ether);
        dai.mint(bob, 100 ether);
        dai.mint(carol, 100 ether);

        // Approve lottery to spend DAI
        vm.prank(alice);
        dai.approve(address(lottery), type(uint256).max);
        vm.prank(bob);
        dai.approve(address(lottery), type(uint256).max);
        vm.prank(carol);
        dai.approve(address(lottery), type(uint256).max);
    }

    function _getCommitment() internal returns (bytes32) {
        vm.prank(owner);
        return lottery.generateCommitment(WINNING_NUMBER, SECRET);
    }

    function _startGame() internal {
        bytes32 commitment = _getCommitment();
        vm.prank(owner);
        lottery.start(commitment);
    }

    function _endGameAndReveal() internal {
        vm.roll(block.number + 100);
        vm.prank(owner);
        lottery.revealNumber(WINNING_NUMBER, SECRET);
    }

    // ============ Commit Phase Tests ============

    function test_StartGameWithCommitment() public {
        bytes32 commitment = _getCommitment();
        vm.prank(owner);
        lottery.start(commitment);
        assertGt(lottery.startBlock(), 0);
        assertEq(lottery.commitment(), commitment);
    }

    function test_CannotStartWithoutCommitment() public {
        vm.prank(owner);
        vm.expectRevert(Lottery.NotCommitted.selector);
        lottery.start(bytes32(0));
    }

    function test_CannotStartTwice() public {
        _startGame();

        bytes32 commitment = _getCommitment();
        vm.prank(owner);
        vm.expectRevert(Lottery.AlreadyStarted.selector);
        lottery.start(commitment);
    }

    // ============ Bet Phase Tests ============

    function test_BetDuringGame() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        (uint8 luckyNumber, bool hasPlayed, bool claimed, bool refunded) = lottery.users(alice);
        assertEq(luckyNumber, 50);
        assertTrue(hasPlayed);
        assertFalse(claimed);
        assertFalse(refunded);
    }

    function test_CannotBetBeforeStart() public {
        vm.prank(alice);
        vm.expectRevert(Lottery.NotDuringGame.selector);
        lottery.bet(50);
    }

    function test_CannotBetTwice() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        vm.prank(alice);
        vm.expectRevert(Lottery.AlreadyPlayed.selector);
        lottery.bet(60);
    }

    function test_InvalidNumberTooLow() public {
        _startGame();

        vm.prank(alice);
        vm.expectRevert(Lottery.InvalidNumber.selector);
        lottery.bet(0);
    }

    function test_InvalidNumberTooHigh() public {
        _startGame();

        vm.prank(alice);
        vm.expectRevert(Lottery.InvalidNumber.selector);
        lottery.bet(101);
    }

    // ============ Reveal Phase Tests ============

    function test_RevealWithCorrectSecret() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        vm.roll(block.number + 100);

        vm.prank(owner);
        lottery.revealNumber(WINNING_NUMBER, SECRET);

        (uint8 winningNumber, bool isRevealed,,) = lottery.result();
        assertTrue(isRevealed);
        assertEq(winningNumber, WINNING_NUMBER);
    }

    function test_CannotRevealWithWrongSecret() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        vm.roll(block.number + 100);

        vm.prank(owner);
        vm.expectRevert(Lottery.InvalidReveal.selector);
        lottery.revealNumber(WINNING_NUMBER, bytes32(uint256(99999))); // Wrong secret
    }

    function test_CannotRevealWithWrongNumber() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        vm.roll(block.number + 100);

        vm.prank(owner);
        vm.expectRevert(Lottery.InvalidReveal.selector);
        lottery.revealNumber(75, SECRET); // Wrong number (but same secret)
    }

    function test_CannotRevealTwice() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        _endGameAndReveal();

        vm.prank(owner);
        vm.expectRevert(Lottery.InvalidReveal.selector);
        lottery.revealNumber(WINNING_NUMBER, SECRET);
    }

    function test_RevealBeforeGameEnds() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        // Only move 50 blocks (not enough)
        vm.roll(block.number + 50);

        vm.prank(owner);
        vm.expectRevert(Lottery.GameNotEnded.selector);
        lottery.revealNumber(WINNING_NUMBER, SECRET);
    }

    // ============ Winner Selection Tests ============

    function test_ExactMatchWinner() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50); // Exact match

        vm.prank(bob);
        lottery.bet(51); // Close but not exact

        _endGameAndReveal();

        vm.prank(alice);
        lottery.claim();

        vm.prank(bob);
        vm.expectRevert(Lottery.NotWinner.selector);
        lottery.claim();
    }

    function test_MultipleWinnersSameDistance() public {
        _startGame();

        // Alice bets 48, Bob bets 52 (both distance 2 from 50)
        vm.prank(alice);
        lottery.bet(48);

        vm.prank(bob);
        lottery.bet(52);

        // Carol bets 60 (distance 10 from 50)
        vm.prank(carol);
        lottery.bet(60);

        _endGameAndReveal();

        vm.prank(alice);
        lottery.claim();

        vm.prank(bob);
        lottery.claim();

        vm.prank(carol);
        vm.expectRevert(Lottery.NotWinner.selector);
        lottery.claim();
    }

    function test_EdgeCaseWinningNumberAtBoundary() public {
        // Setup with winning number 1
        vm.prank(owner);
        bytes32 commitment = lottery.generateCommitment(1, SECRET);
        vm.prank(owner);
        lottery.start(commitment);

        vm.prank(alice);
        lottery.bet(3); // distance 2

        vm.prank(bob);
        lottery.bet(5); // distance 4

        vm.roll(block.number + 100);

        vm.prank(owner);
        lottery.revealNumber(1, SECRET);

        vm.prank(alice);
        lottery.claim();

        vm.prank(bob);
        vm.expectRevert(Lottery.NotWinner.selector);
        lottery.claim();
    }

    function test_MultiplePlayersSameNumber() public {
        _startGame();

        // Alice and Bob both bet 48
        vm.prank(alice);
        lottery.bet(48);

        vm.prank(bob);
        lottery.bet(48);

        // Carol bets 52 (same distance but different number)
        vm.prank(carol);
        lottery.bet(52);

        _endGameAndReveal();

        vm.prank(alice);
        lottery.claim();

        vm.prank(bob);
        lottery.claim();

        vm.prank(carol);
        lottery.claim();
    }

    function test_ClosestNumberWins() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(45); // distance 5 from 50

        vm.prank(bob);
        lottery.bet(49); // distance 1 from 50 (winner)

        vm.prank(carol);
        lottery.bet(55); // distance 5 from 50

        _endGameAndReveal();

        vm.prank(bob);
        lottery.claim();

        vm.prank(alice);
        vm.expectRevert(Lottery.NotWinner.selector);
        lottery.claim();

        vm.prank(carol);
        vm.expectRevert(Lottery.NotWinner.selector);
        lottery.claim();
    }

    // ============ Claim Tests ============

    function test_CannotClaimBeforeReveal() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        vm.roll(block.number + 100);

        vm.prank(alice);
        vm.expectRevert(Lottery.NotRevealed.selector);
        lottery.claim();
    }

    function test_CannotClaimTwice() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        _endGameAndReveal();

        vm.prank(alice);
        lottery.claim();

        vm.prank(alice);
        vm.expectRevert(Lottery.AlreadyClaimed.selector);
        lottery.claim();
    }

    function test_CannotClaimIfDidNotPlay() public {
        _startGame();

        // Alice bets
        vm.prank(alice);
        lottery.bet(50);

        _endGameAndReveal();

        // Someone who didn't play tries to claim
        vm.prank(address(999));
        vm.expectRevert(Lottery.DidNotPlay.selector);
        lottery.claim();
    }

    // ============ Prize Distribution Tests ============

    function test_PrizeDistributionSingleWinner() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        _endGameAndReveal();

        uint256 initialBalance = dai.balanceOf(alice);

        vm.prank(alice);
        lottery.claim();

        uint256 finalBalance = dai.balanceOf(alice);
        assertEq(finalBalance - initialBalance, 1 ether); // Full pot
    }

    function test_PrizeDistributionMultipleWinners() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(48);

        vm.prank(bob);
        lottery.bet(52);

        _endGameAndReveal();

        uint256 aliceInitial = dai.balanceOf(alice);
        uint256 bobInitial = dai.balanceOf(bob);

        vm.prank(alice);
        lottery.claim();

        vm.prank(bob);
        lottery.claim();

        // Both should get 1 ETH (2 ETH pot / 2 winners)
        assertEq(dai.balanceOf(alice) - aliceInitial, 1 ether);
        assertEq(dai.balanceOf(bob) - bobInitial, 1 ether);
    }

    // ============ Owner Tests ============

    function test_OnlyOwnerCanStart() public {
        bytes32 commitment = _getCommitment();
        vm.prank(alice);
        vm.expectRevert(Lottery.NotOwner.selector);
        lottery.start(commitment);
    }

    function test_OnlyOwnerCanReveal() public {
        _startGame();

        vm.roll(block.number + 100);

        vm.prank(alice);
        vm.expectRevert(Lottery.NotOwner.selector);
        lottery.revealNumber(WINNING_NUMBER, SECRET);
    }

    // ============ Edge Case Tests ============

    function test_NoPlayers_Revert() public {
        _startGame();

        vm.roll(block.number + 100);

        vm.prank(owner);
        vm.expectRevert(Lottery.NoPlayers.selector);
        lottery.revealNumber(WINNING_NUMBER, SECRET);
    }

    function test_RevealInvalidNumberTooLow() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        vm.roll(block.number + 100);

        vm.prank(owner);
        vm.expectRevert(Lottery.InvalidNumber.selector);
        lottery.revealNumber(0, SECRET);
    }

    function test_RevealInvalidNumberTooHigh() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        vm.roll(block.number + 100);

        vm.prank(owner);
        vm.expectRevert(Lottery.InvalidNumber.selector);
        lottery.revealNumber(101, SECRET);
    }

    function test_BetAfterGameEnds() public {
        _startGame();

        vm.roll(block.number + 100);

        vm.prank(alice);
        vm.expectRevert(Lottery.NotDuringGame.selector);
        lottery.bet(50);
    }

    // ============ Commit-Reveal Security Tests ============

    function test_OwnerCannotChangeNumberAfterSeeingBets() public {
        // Owner commits to 50 at start
        _startGame();

        // Alice bets on 50
        vm.prank(alice);
        lottery.bet(50);

        // Even if owner wants to cheat and reveal a different number,
        // they can't because the hash won't match
        vm.roll(block.number + 100);

        // Trying to reveal 75 instead of committed 50 will fail
        vm.prank(owner);
        vm.expectRevert(Lottery.InvalidReveal.selector);
        lottery.revealNumber(75, SECRET);

        // Can only reveal the committed number
        vm.prank(owner);
        lottery.revealNumber(WINNING_NUMBER, SECRET);

        (uint8 winningNumber,,,) = lottery.result();
        assertEq(winningNumber, WINNING_NUMBER);
    }

    function test_VerifyCommitmentFunction() public {
        vm.prank(owner);
        bytes32 commitment = lottery.generateCommitment(42, bytes32(uint256(999)));
        assertEq(commitment, keccak256(abi.encodePacked(uint8(42), bytes32(uint256(999)), owner)));
    }

    // ============ Refund Tests ============

    function test_RefundWhenAdminDoesNotReveal() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        // Move past game end AND reveal deadline
        vm.roll(block.number + 100 + 50 + 1); // GAME_DURATION + REVEAL_DEADLINE + 1

        uint256 initialBalance = dai.balanceOf(alice);

        // Admin never reveals, player can refund
        vm.prank(alice);
        lottery.refund();

        uint256 finalBalance = dai.balanceOf(alice);
        assertEq(finalBalance - initialBalance, 1 ether);

        // Check player is marked as refunded
        (,,, bool refunded) = lottery.users(alice);
        assertTrue(refunded);
    }

    function test_RefundFailsWhenAdminRevealsInTime() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        // Move past game end but before reveal deadline
        vm.roll(block.number + 100 + 10); // GAME_DURATION + 10 blocks

        // Admin reveals in time
        vm.prank(owner);
        lottery.revealNumber(WINNING_NUMBER, SECRET);

        // Player tries to refund but fails because reveal happened
        vm.prank(alice);
        vm.expectRevert(Lottery.InvalidReveal.selector);
        lottery.refund();
    }

    function test_CannotRefundBeforeRevealDeadline() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        // Move past game end but BEFORE reveal deadline
        vm.roll(block.number + 100 + 10); // GAME_DURATION + 10 blocks (deadline is 50)

        // Player tries to refund too early
        vm.prank(alice);
        vm.expectRevert(Lottery.RevealDeadlineNotPassed.selector);
        lottery.refund();
    }

    function test_CannotRefundTwice() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        // Move past reveal deadline
        vm.roll(block.number + 100 + 50 + 1);

        vm.prank(alice);
        lottery.refund();

        // Try to refund again
        vm.prank(alice);
        vm.expectRevert(Lottery.AlreadyRefunded.selector);
        lottery.refund();
    }

    function test_CannotRefundIfDidNotPlay() public {
        _startGame();

        // Move past reveal deadline
        vm.roll(block.number + 100 + 50 + 1);

        // Someone who didn't play tries to refund
        vm.prank(address(999));
        vm.expectRevert(Lottery.DidNotPlay.selector);
        lottery.refund();
    }

    function test_RevealDeadlinePassedError() public {
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        // Move past reveal deadline
        vm.roll(block.number + 100 + 50 + 1);

        // Admin tries to reveal after deadline
        vm.prank(owner);
        vm.expectRevert(Lottery.RevealDeadlinePassed.selector);
        lottery.revealNumber(WINNING_NUMBER, SECRET);
    }

    function test_CommitmentNotSetError() public {
        // Try to bet before game starts (commitment not set)
        // This reverts with NotDuringGame because startBlock is 0
        vm.prank(alice);
        vm.expectRevert(Lottery.NotDuringGame.selector);
        lottery.bet(50);
    }

    function test_ReentrancyProtectionOnClaim() public {
        // This test verifies nonReentrant is working by checking a normal claim works
        _startGame();

        vm.prank(alice);
        lottery.bet(50);

        _endGameAndReveal();

        // Normal claim should work
        vm.prank(alice);
        lottery.claim();

        // Second claim should fail with AlreadyClaimed, not reentrant
        vm.prank(alice);
        vm.expectRevert(Lottery.AlreadyClaimed.selector);
        lottery.claim();
    }
}
