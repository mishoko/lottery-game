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
    }

    struct GameResult {
        uint8 winningNumber;
        bool isRevealed;
        uint256 winningDistance;
        uint256 prizePerWinner;
    }

    IERC20 public constant DAI = IERC20(0x1111111111111111111111111111111111111111);
    uint64 public constant GAME_DURATION = 100;
    uint256 public constant BET_AMOUNT = 1e18; // 1 DAI

    address public immutable owner;
    uint64 public startBlock;

    GameResult public result;
    uint256 public totalPlayers;

    mapping(address => UserInfo) public users;
    mapping(uint8 => address[]) public numberToPlayers;

    // ============ Errors ============
    error NotOwner();
    error NotDuringGame();
    error GameNotEnded();
    error AlreadyStarted();
    error InvalidNumber();
    error AlreadyPlayed();
    error TransferFailed();
    error AlreadyRevealed();
    error NoPlayers();
    error NotRevealed();
    error DidNotPlay();
    error AlreadyClaimed();
    error NotWinner();

    constructor() {
        owner = msg.sender;
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

    function start() external onlyOwner {
        require(startBlock == 0, AlreadyStarted());
        startBlock = uint64(block.number);
    }

    function bet(uint8 _luckyNumber) external duringGame {
        _validateNumber(_luckyNumber);
        require(!users[msg.sender].hasPlayed, AlreadyPlayed());

        users[msg.sender] = UserInfo({
            luckyNumber: _luckyNumber,
            hasPlayed: true,
            claimed: false
        });
        numberToPlayers[_luckyNumber].push(msg.sender);
        unchecked { ++totalPlayers; }
        require(DAI.transferFrom(msg.sender, address(this), BET_AMOUNT), TransferFailed());
    }

    function revealNumber(uint8 _winningNumber) external onlyOwner afterGame {
        require(!result.isRevealed, AlreadyRevealed());
        _validateNumber(_winningNumber);

        uint256 minDistance = type(uint256).max;
        uint256 winnerCount = 0;

        // Check all possible numbers 1-100 (constant 100 iterations vs O(n) players)
        for (uint8 num = 1; num <= 100; ) {
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
            unchecked { ++num; }
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
        require(DAI.transfer(msg.sender, gameResult.prizePerWinner), TransferFailed());
    }

    function getPlayerCount() external view returns (uint256) {
        return totalPlayers;
    }

    function getPlayersByNumber(uint8 _number) external view returns (address[] memory) {
        return numberToPlayers[_number];
    }

    function _onlyOwner() internal view {
        require(msg.sender == owner, NotOwner());
    }

    function _duringGame() internal view {
        require(uint64(block.number) >= startBlock && uint64(block.number) < startBlock + GAME_DURATION, NotDuringGame());
    }

    function _afterGame() internal view {
        require(uint64(block.number) >= startBlock + GAME_DURATION, GameNotEnded());
    }

    function _distance(uint8 a, uint8 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }

    function _validateNumber(uint8 _number) internal pure {
        require(_number >= 1 && _number <= 100, InvalidNumber());
    }
}
