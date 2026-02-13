// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "../src/Lottery.sol";

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
    
    // ============ Basic Functionality Tests ============
    
    function test_StartGame() public {
        vm.prank(owner);
        lottery.start();
        assertGt(lottery.startBlock(), 0);
    }
    
    function test_BetDuringGame() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(50);
        
        (uint8 luckyNumber, bool hasPlayed, bool claimed) = lottery.users(alice);
        assertEq(luckyNumber, 50);
        assertTrue(hasPlayed);
        assertFalse(claimed);
    }
    
    function test_CannotBetBeforeStart() public {
        vm.prank(alice);
        vm.expectRevert(Lottery.NotDuringGame.selector);
        lottery.bet(50);
    }
    
    function test_CannotBetTwice() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(50);
        
        vm.prank(alice);
        vm.expectRevert(Lottery.AlreadyPlayed.selector);
        lottery.bet(60);
    }
    
    function test_InvalidNumberTooLow() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        vm.expectRevert(Lottery.InvalidNumber.selector);
        lottery.bet(0);
    }
    
    function test_InvalidNumberTooHigh() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        vm.expectRevert(Lottery.InvalidNumber.selector);
        lottery.bet(101);
    }
    
    // ============ Winner Selection Tests ============
    
    function test_ExactMatchWinner() public {
        // Setup
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(50);
        
        vm.prank(bob);
        lottery.bet(51);
        
        // Move forward 100 blocks
        vm.roll(block.number + 100);
        
        // Reveal winning number 50
        vm.prank(owner);
        lottery.revealNumber(50);
        
        // Alice should be the only winner (exact match)
        vm.prank(alice);
        lottery.claim();
        
        // Bob should not be able to claim
        vm.prank(bob);
        vm.expectRevert(Lottery.NotWinner.selector);
        lottery.claim();
    }
    
    function test_MultipleWinnersSameDistance() public {
        // Setup
        vm.prank(owner);
        lottery.start();
        
        // Alice bets 48, Bob bets 52 (both distance 2 from 50)
        vm.prank(alice);
        lottery.bet(48);
        
        vm.prank(bob);
        lottery.bet(52);
        
        // Carol bets 60 (distance 10 from 50)
        vm.prank(carol);
        lottery.bet(60);
        
        // Move forward 100 blocks
        vm.roll(block.number + 100);
        
        // Reveal winning number 50
        vm.prank(owner);
        lottery.revealNumber(50);
        
        // Alice and Bob should both be winners
        vm.prank(alice);
        lottery.claim();
        
        vm.prank(bob);
        lottery.claim();
        
        // Carol should not be winner
        vm.prank(carol);
        vm.expectRevert(Lottery.NotWinner.selector);
        lottery.claim();
    }
    
    function test_EdgeCaseWinningNumberAtBoundary() public {
        // Setup
        vm.prank(owner);
        lottery.start();
        
        // Winning number is 1
        vm.prank(alice);
        lottery.bet(3); // distance 2
        
        vm.prank(bob);
        lottery.bet(5); // distance 4
        
        // Move forward 100 blocks
        vm.roll(block.number + 100);
        
        // Reveal winning number 1
        vm.prank(owner);
        lottery.revealNumber(1);
        
        // Alice should be winner (closest)
        vm.prank(alice);
        lottery.claim();
        
        // Bob should not be winner
        vm.prank(bob);
        vm.expectRevert(Lottery.NotWinner.selector);
        lottery.claim();
    }
    
    function test_MultiplePlayersSameNumber() public {
        // Setup
        vm.prank(owner);
        lottery.start();
        
        // Alice and Bob both bet 48
        vm.prank(alice);
        lottery.bet(48);
        
        vm.prank(bob);
        lottery.bet(48);
        
        // Carol bets 52 (same distance but different number)
        vm.prank(carol);
        lottery.bet(52);
        
        // Move forward 100 blocks
        vm.roll(block.number + 100);
        
        // Reveal winning number 50
        vm.prank(owner);
        lottery.revealNumber(50);
        
        // All three should be winners (all distance 2)
        vm.prank(alice);
        lottery.claim();
        
        vm.prank(bob);
        lottery.claim();
        
        vm.prank(carol);
        lottery.claim();
    }
    
    function test_ClosestNumberWins() public {
        // Setup
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(45); // distance 5 from 50
        
        vm.prank(bob);
        lottery.bet(49); // distance 1 from 50 (winner)
        
        vm.prank(carol);
        lottery.bet(55); // distance 5 from 50
        
        // Move forward 100 blocks
        vm.roll(block.number + 100);
        
        // Reveal winning number 50
        vm.prank(owner);
        lottery.revealNumber(50);
        
        // Only Bob should win
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
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(50);
        
        vm.roll(block.number + 100);
        
        // Try to claim before reveal
        vm.prank(alice);
        vm.expectRevert(Lottery.NotRevealed.selector);
        lottery.claim();
    }
    
    function test_CannotClaimTwice() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(50);
        
        vm.roll(block.number + 100);
        
        vm.prank(owner);
        lottery.revealNumber(50);
        
        vm.prank(alice);
        lottery.claim();
        
        // Try to claim again
        vm.prank(alice);
        vm.expectRevert(Lottery.AlreadyClaimed.selector);
        lottery.claim();
    }
    
    function test_CannotClaimIfDidNotPlay() public {
        vm.prank(owner);
        lottery.start();
        
        // Alice bets
        vm.prank(alice);
        lottery.bet(50);
        
        vm.roll(block.number + 100);
        
        vm.prank(owner);
        lottery.revealNumber(50);
        
        // Someone who didn't play tries to claim
        vm.prank(address(999));
        vm.expectRevert(Lottery.DidNotPlay.selector);
        lottery.claim();
    }
    
    // ============ Prize Distribution Tests ============
    
    function test_PrizeDistributionSingleWinner() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(50);
        
        vm.roll(block.number + 100);
        
        vm.prank(owner);
        lottery.revealNumber(50);
        
        uint256 initialBalance = dai.balanceOf(alice);
        
        vm.prank(alice);
        lottery.claim();
        
        uint256 finalBalance = dai.balanceOf(alice);
        assertEq(finalBalance - initialBalance, 1 ether); // Full pot
    }
    
    function test_PrizeDistributionMultipleWinners() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(48);
        
        vm.prank(bob);
        lottery.bet(52);
        
        vm.roll(block.number + 100);
        
        vm.prank(owner);
        lottery.revealNumber(50);
        
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
        vm.prank(alice);
        vm.expectRevert(Lottery.NotOwner.selector);
        lottery.start();
    }
    
    function test_OnlyOwnerCanReveal() public {
        vm.prank(owner);
        lottery.start();
        
        vm.roll(block.number + 100);
        
        vm.prank(alice);
        vm.expectRevert(Lottery.NotOwner.selector);
        lottery.revealNumber(50);
    }
    
    function test_CannotStartTwice() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(owner);
        vm.expectRevert(Lottery.AlreadyStarted.selector);
        lottery.start();
    }
    
    function test_CannotRevealTwice() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(50);
        
        vm.roll(block.number + 100);
        
        vm.prank(owner);
        lottery.revealNumber(50);
        
        vm.prank(owner);
        vm.expectRevert(Lottery.AlreadyRevealed.selector);
        lottery.revealNumber(60);
    }
    
    // ============ Edge Case Tests ============
    
    function test_NoPlayers_Revert() public {
        vm.prank(owner);
        lottery.start();
        
        vm.roll(block.number + 100);
        
        vm.prank(owner);
        vm.expectRevert(Lottery.NoPlayers.selector);
        lottery.revealNumber(50);
    }
    
    function test_RevealInvalidNumberTooLow() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(50);
        
        vm.roll(block.number + 100);
        
        vm.prank(owner);
        vm.expectRevert(Lottery.InvalidNumber.selector);
        lottery.revealNumber(0);
    }
    
    function test_RevealInvalidNumberTooHigh() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(50);
        
        vm.roll(block.number + 100);
        
        vm.prank(owner);
        vm.expectRevert(Lottery.InvalidNumber.selector);
        lottery.revealNumber(101);
    }
    
    function test_RevealBeforeGameEnds() public {
        vm.prank(owner);
        lottery.start();
        
        vm.prank(alice);
        lottery.bet(50);
        
        // Only move 50 blocks (not enough)
        vm.roll(block.number + 50);
        
        vm.prank(owner);
        vm.expectRevert(Lottery.GameNotEnded.selector);
        lottery.revealNumber(50);
    }
    
    function test_BetAfterGameEnds() public {
        vm.prank(owner);
        lottery.start();
        
        vm.roll(block.number + 100);
        
        vm.prank(alice);
        vm.expectRevert(Lottery.NotDuringGame.selector);
        lottery.bet(50);
    }
}
