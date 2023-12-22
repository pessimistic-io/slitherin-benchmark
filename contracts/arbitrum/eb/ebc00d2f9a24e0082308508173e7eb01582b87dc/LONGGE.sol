// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./ERC20.sol";

contract LONGGE is ERC20, Ownable {
    uint256 public constant maxSupply = 220000000000 * 10 ** 18; // 220b
    uint256 public prizePool = 50000000000 * 10 ** 18; // 50b
    uint256 public teamSupply = 20000000000 * 10 ** 18; // 20b
    uint256 public initialMintAmount = 5000000 * 10 ** 18; // 5m
    uint256 public longCost = 250000 * 10 ** 18; // 250k
    uint256 public lastLongUpdate;
    address public longOwner;
    string public long = "FUCK LONG";
    mapping(address => uint256) public lastMintValue;
    mapping(address => uint256) public lastMintTime;

    event LongUpdated(
        address indexed user,
        string message,
        uint256 newLongCost
    );
    event PrizePoolClaimed(address indexed longOwner, uint256 amount);
    event Log(string func, uint gas);

    modifier maxLength(string memory message) {
        require(
            bytes(message).length <= 26,
            "Message must be 26 characters or less"
        );
        _;
    }

    constructor() ERC20("LONGGE", "LONGGE") {
        _mint(address(this), maxSupply);
        _transfer(address(this), msg.sender, teamSupply);
        longOwner = msg.sender;
        lastLongUpdate = block.timestamp;
    }

    function mintLONGGE() external {
        require(
            block.timestamp >= lastMintTime[msg.sender] + 1 days,
            "You can only mint once every 24 hours"
        );
        uint256 mintAmount;
        if (lastMintValue[msg.sender] == 0) {
            mintAmount = initialMintAmount;
        } else {
            mintAmount = lastMintValue[msg.sender] / 2;
        }
        require(mintAmount > 0, "Mint amount is too small");
        require(
            balanceOf(address(this)) - prizePool >= mintAmount,
            "Not enough LONGGE left to mint"
        );
        lastMintValue[msg.sender] = mintAmount;
        lastMintTime[msg.sender] = block.timestamp;
        _transfer(address(this), msg.sender, mintAmount);
    }

    function setLong(string memory message) external maxLength(message) {
        require(bytes(message).length > 0, "Message cannot be empty");
        if (msg.sender != longOwner) {
            require(
                balanceOf(msg.sender) >= longCost,
                "Insufficient LONGGE to set LONG"
            );
            IERC20(address(this)).transferFrom(
                msg.sender,
                address(this),
                longCost
            );
            _burn(address(this), longCost);
            longCost = longCost + (longCost * 5000) / 10000;
        }
        long = message;
        longOwner = msg.sender;
        lastLongUpdate = block.timestamp;
        emit LongUpdated(msg.sender, message, longCost);
    }

    function claimPrizePool() external {
        require(
            block.timestamp >= lastLongUpdate + 7 days,
            "Prizepool can be claimed if 7 days have passed without a LONG update"
        );
        require(
            msg.sender == longOwner,
            "Only the current longOwner can claim the prizepool"
        );
        uint256 claimAmount = prizePool;
        prizePool = 0;
        _transfer(address(this), msg.sender, claimAmount);
        emit PrizePoolClaimed(msg.sender, prizePool);
    }

    fallback() external payable {
        emit Log("fallback", gasleft());
    }

    receive() external payable {
        emit Log("receive", gasleft());
    }

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    function burn(uint256 value) external {
        _burn(msg.sender, value);
    }
}

