// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./Ownable.sol";
import "./ERC20Capped.sol";

contract Claps is ERC20Capped, Ownable {
    uint256 public constant maxSupply = 220000000000 * 10 ** 18; // 220b
		uint256 public prizePool = 50000000000 * 10 ** 18; // 50b
		uint256 public teamSupply = 20000000000 * 10 ** 18; // 20b
    uint256 public initialMintAmount = 5000000 * 10 ** 18; // 5m
    uint256 public clapCost = 250000 * 10 ** 18; // 250k
    uint256 public lastClapUpdate;
    address public clapOwner;
    string public clap = "Clap";
    mapping(address => uint256) public lastMintValue;
    mapping(address => uint256) public lastMintTime;

    event ClapUpdated(address indexed user, string message, uint256 newClapCost);
    event PrizePoolClaimed(address indexed clapOwner, uint256 amount);
		event Log(string func, uint gas);

    modifier maxLength(string memory message) {
        require(bytes(message).length <= 50, "Message must be 50 characters or less");
        _;
    }

    constructor() ERC20("CLAPS", "CLAPS") ERC20Capped(maxSupply) {
        _mint(address(this), maxSupply); 
				_transfer(address(this), msg.sender, teamSupply); 
        clapOwner = msg.sender; 
    }

    function mintClaps() external {
        require(block.timestamp >= lastMintTime[msg.sender] + 1 days, "You can only mint once every 24 hours");
        uint256 mintAmount;
        if (lastMintValue[msg.sender] == 0) {
            mintAmount = initialMintAmount;
        } else {
						mintAmount = lastMintValue[msg.sender] / 2;
        }
        require(mintAmount > 0, "Mint amount is too small");
				require(balanceOf(address(this)) - prizePool >= mintAmount, "Not enough CLAPS left to mint");
        lastMintValue[msg.sender] = mintAmount;
				lastMintTime[msg.sender] = block.timestamp;
				_transfer(address(this), msg.sender, mintAmount);
    }

    function setClap(string memory message) external maxLength(message) {
				require(bytes(message).length > 0, "Message cannot be empty");
        if (msg.sender != clapOwner) {
            require(balanceOf(msg.sender) >= clapCost, "Insufficient CLAPS to set CLAP");
            IERC20(address(this)).transferFrom(msg.sender, address(this), clapCost);
						_burn(address(this), clapCost);
						clapCost = clapCost + (clapCost * 5000) / 10000;
        }
        clap = message;
        clapOwner = msg.sender;
        lastClapUpdate = block.timestamp;
        emit ClapUpdated(msg.sender, message, clapCost);
    }

    function claimPrizePool() external {
        require(block.timestamp >= lastClapUpdate + 7 days, "Prizepool can be claimed if 7 days have passed without a CLAP update");
        require(msg.sender == clapOwner, "Only the current clapOwner can claim the prizepool");
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
