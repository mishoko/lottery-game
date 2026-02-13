// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract Lottery {
    struct UserInfo {
        uint8 luckyNumber;
        bool hasPlayed;
        bool claimed;
        bool refunded;
    }

    struct GameResult {
        uint8 winningNumber;
        bool isRevealed;
        uint256 winningDistance;
        uint256 prizePerWinner;
    }

    uint64 public constant GAME_DURATION = 100;
    uint64 public constant REVEAL_DEADLINE = 50; // 50 blocks after game ends to reveal
    uint256 public constant BET_AMOUNT = 1e18; // 1 DAI
    uint8 public constant MIN_NUMBER = 1;
    uint8 public constant MAX_NUMBER = 100;

    IERC20 public immutable dai;
    address public immutable owner;
    uint64 public startBlock;
    bytes32 public commitment; // Hash of (winningNumber + secret)

    GameResult public result;
    uint256 public totalPlayers;

    mapping(address => UserInfo) public users;
    mapping(uint8 => address[]) public numberToPlayers;

    error NotOwner();
    error NotDuringGame();
    error GameNotEnded();
    error AlreadyStarted();
    error InvalidNumber();
    error AlreadyPlayed();
    error TransferFailed();
    error InvalidReveal();
    error NoPlayers();
    error NotRevealed();
    error DidNotPlay();
    error AlreadyClaimed();
    error NotWinner();
    error AlreadyCommitted();
    error NotCommitted();
    error RevealDeadlinePassed();
    error RevealDeadlineNotPassed();
    error AlreadyRefunded();
    error CommitmentNotSet();

    constructor(address _dai) {
        owner = msg.sender;
        dai = IERC20(_dai);
    }

    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    modifier duringGame() {
        _duringGame();
        _;
    }

    modifier afterGame() {
        _afterGame();
        _;
    }

    function start(bytes32 _commitment) external onlyOwner {
        require(startBlock == 0, AlreadyStarted());
        require(_commitment != bytes32(0), NotCommitted());
        startBlock = uint64(block.number);
        commitment = _commitment;
    }

    function bet(uint8 _luckyNumber) external duringGame {
        require(commitment != bytes32(0), CommitmentNotSet());
        _validateNumber(_luckyNumber);
        require(!users[msg.sender].hasPlayed, AlreadyPlayed());

        users[msg.sender] = UserInfo({luckyNumber: _luckyNumber, hasPlayed: true, claimed: false, refunded: false});
        numberToPlayers[_luckyNumber].push(msg.sender);
        unchecked {
            ++totalPlayers;
        }
        require(dai.transferFrom(msg.sender, address(this), BET_AMOUNT), TransferFailed());
    }

    function revealNumber(uint8 _winningNumber, bytes32 _secret) external onlyOwner afterGame {
        require(!result.isRevealed, InvalidReveal());
        require(block.number <= startBlock + GAME_DURATION + REVEAL_DEADLINE, RevealDeadlinePassed());
        _validateNumber(_winningNumber);

        // Verify the reveal matches the commitment
        bytes32 revealedHash = keccak256(abi.encodePacked(_winningNumber, _secret, msg.sender));
        require(revealedHash == commitment, InvalidReveal());

        uint256 minDistance = type(uint256).max;
        uint256 winnerCount = 0;

        // Check all possible numbers MIN_NUMBER-MAX_NUMBER (constant MAX_NUMBER iterations vs O(n) players)
        for (uint8 num = MIN_NUMBER; num <= MAX_NUMBER;) {
            uint256 count = numberToPlayers[num].length;
            if (count > 0) {
                uint256 distance = _distance(num, _winningNumber);
                if (distance < minDistance) {
                    minDistance = distance;
                    winnerCount = count;
                } else if (distance == minDistance) {
                    winnerCount += count;
                }
            }
            unchecked {
                ++num;
            }
        }

        require(winnerCount > 0, NoPlayers());

        result.winningNumber = _winningNumber;
        result.winningDistance = minDistance;
        result.prizePerWinner = (totalPlayers * BET_AMOUNT) / winnerCount;
        result.isRevealed = true;
    }

    function claim() external {
        GameResult memory gameResult = result;
        require(gameResult.isRevealed, NotRevealed());

        UserInfo storage user = users[msg.sender];
        require(user.hasPlayed, DidNotPlay());
        require(!user.claimed, AlreadyClaimed());
        require(_distance(user.luckyNumber, gameResult.winningNumber) == gameResult.winningDistance, NotWinner());

        user.claimed = true;
        require(dai.transfer(msg.sender, gameResult.prizePerWinner), TransferFailed());
    }

    // Allow players to refund if admin doesn't reveal in time
    function refund() external {
        require(startBlock != 0, GameNotEnded());
        require(!result.isRevealed, InvalidReveal());
        require(block.number > startBlock + GAME_DURATION + REVEAL_DEADLINE, RevealDeadlineNotPassed());
        
        UserInfo storage user = users[msg.sender];
        require(user.hasPlayed, DidNotPlay());
        require(!user.refunded, AlreadyRefunded());
        
        user.refunded = true;
        require(dai.transfer(msg.sender, BET_AMOUNT), TransferFailed());
    }

    function getPlayerCount() external view returns (uint256) {
        return totalPlayers;
    }

    function getPlayersByNumber(uint8 _number) external view returns (address[] memory) {
        return numberToPlayers[_number];
    }

    // Helper function to generate commitment off-chain
    function generateCommitment(uint8 _winningNumber, bytes32 _secret)
        external
        view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(_winningNumber, _secret, msg.sender));
    }

    function _onlyOwner() internal view {
        require(msg.sender == owner, NotOwner());
    }

    function _duringGame() internal view {
        require(
            startBlock != 0 && uint64(block.number) >= startBlock && uint64(block.number) < startBlock + GAME_DURATION,
            NotDuringGame()
        );
    }

    function _afterGame() internal view {
        require(uint64(block.number) >= startBlock + GAME_DURATION, GameNotEnded());
    }

    function _distance(uint8 a, uint8 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _validateNumber(uint8 _number) internal pure {
        require(_number >= MIN_NUMBER && _number <= MAX_NUMBER, InvalidNumber());
    }
}
