// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

contract Lottery {
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
        require(msg.sender == owner, "Not owner");
    }
    
    modifier duringGame() {
        _duringGame();
        _;
    }
    
    function _duringGame() internal view {
        require(uint64(block.number) >= startBlock && uint64(block.number) < startBlock + GAME_DURATION, "Not during game");
    }
    
    modifier afterGame() {
        _afterGame();
        _;
    }
    
    function _afterGame() internal view {
        require(uint64(block.number) >= startBlock + GAME_DURATION, "Game not ended");
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    function start() external onlyOwner {
        require(startBlock == 0, "Already started");
        startBlock = uint64(block.number);
    }
    
    function bet(uint8 _luckyNumber) external duringGame {
        require(_luckyNumber >= 1 && _luckyNumber <= 100, "Number 1-100");
        require(!users[msg.sender].hasPlayed, "Already played");
        
        users[msg.sender] = UserInfo({
            luckyNumber: _luckyNumber,
            hasPlayed: true,
            claimed: false
        });
        players.push(msg.sender);
        
        require(DAI.transferFrom(msg.sender, address(this), BET_AMOUNT), "Transfer failed");
    }
    
    function revealNumber(uint8 _winningNumber) external onlyOwner afterGame {
        require(!result.isRevealed, "Already revealed");
        require(_winningNumber >= 1 && _winningNumber <= 100, "Invalid number");
        
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
        
        require(winnerCount > 0, "No players");
        
        result.winningNumber = _winningNumber;
        result.winningDistance = minDistance;
        result.prizePerWinner = (players.length * BET_AMOUNT) / winnerCount;
        result.isRevealed = true;
    }
    
    function claim() external {
        require(result.isRevealed, "Not revealed");
        
        UserInfo storage user = users[msg.sender];
        require(user.hasPlayed, "Did not play");
        require(!user.claimed, "Already claimed");
        require(_distance(user.luckyNumber, result.winningNumber) == result.winningDistance, "Not a winner");
        
        user.claimed = true;
        require(DAI.transfer(msg.sender, result.prizePerWinner), "Transfer failed");
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
