// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract Lottery {
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
    
    IERC20 public constant DAI = IERC20(0x1111111111111111111111111111111111111111); // whatever the DAI address is on respective chain
    
    address public owner;
    uint64 public startBlock; // can store blocks for billions of years
    uint64 public constant GAME_DURATION = 100;
    uint256 public constant BET_AMOUNT = 1e18; // 1 DAI
    
    struct UserInfo {
        uint8 luckyNumber;
        bool hasPlayed;
        bool claimed;
    }
    
    mapping(address => UserInfo) public users;
    address[] public players;
    
    struct GameResult {
        uint8 winningNumber;
        bool isRevealed;
        uint256 winningDistance;
        uint256 prizePerWinner;
    }
    GameResult public result;
    
    modifier onlyOwner() {
        _onlyOwner();
        _;
    }
    
    function _onlyOwner() internal view {
        require(msg.sender == owner, NotOwner());
    }
    
    modifier duringGame() {
        _duringGame();
        _;
    }
    
    function _duringGame() internal view {
        require(uint64(block.number) >= startBlock && uint64(block.number) < startBlock + GAME_DURATION, NotDuringGame());
    }
    
    modifier afterGame() {
        _afterGame();
        _;
    }
    
    function _afterGame() internal view {
        require(uint64(block.number) >= startBlock + GAME_DURATION, GameNotEnded());
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    function start() external onlyOwner {
        require(startBlock == 0, AlreadyStarted());
        startBlock = uint64(block.number);
    }
    
    function bet(uint8 _luckyNumber) external duringGame {
        require(_luckyNumber >= 1 && _luckyNumber <= 100, InvalidNumber());
        require(!users[msg.sender].hasPlayed, AlreadyPlayed());
        
        users[msg.sender] = UserInfo({
            luckyNumber: _luckyNumber,
            hasPlayed: true,
            claimed: false
        });
        players.push(msg.sender);
        require(DAI.transferFrom(msg.sender, address(this), BET_AMOUNT), TransferFailed());
    }
    
    function revealNumber(uint8 _winningNumber) external onlyOwner afterGame {
        require(!result.isRevealed, AlreadyRevealed());
        require(_winningNumber >= 1 && _winningNumber <= 100, InvalidNumber());

        uint256 minDistance = type(uint256).max;
        uint256 winnerCount = 0;

        for (uint256 i = 0; i < players.length; ) {
            uint256 distance = _distance(users[players[i]].luckyNumber, _winningNumber);
            if (distance < minDistance) {
                minDistance = distance;
                winnerCount = 1;
            } else if (distance == minDistance) {
                winnerCount++;
            }
            unchecked { ++i; }
        }

        require(winnerCount > 0, NoPlayers());

        result.winningNumber = _winningNumber;
        result.winningDistance = minDistance;
        result.prizePerWinner = (players.length * BET_AMOUNT) / winnerCount;
        result.isRevealed = true;
    }
    
    function claim() external {
        require(result.isRevealed, NotRevealed());

        UserInfo storage user = users[msg.sender];
        require(user.hasPlayed, DidNotPlay());
        require(!user.claimed, AlreadyClaimed());
        require(_distance(user.luckyNumber, result.winningNumber) == result.winningDistance, NotWinner());

        user.claimed = true;
        require(DAI.transfer(msg.sender, result.prizePerWinner), TransferFailed());
    }
    
    function _distance(uint8 a, uint8 b) internal pure returns (uint256) {
        return a > b ? a - b : b - a;
    }
    
    function getPlayers() external view returns (address[] memory) {
        return players;
    }
    
    function getPlayerCount() external view returns (uint256) {
        return players.length;
    }
}
