// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./Ownable.sol";
import "./ERC20Capped.sol";

contract Captain is ERC20Capped, Ownable {
    uint256 public constant maxSupply = 220000000000 * 10 ** 18; // 220b
    uint256 public prizePool = 50000000000 * 10 ** 18; // 50b
    uint256 public teamSupply = 20000000000 * 10 ** 18; // 20b
    uint256 public initialMintAmount = 5000000 * 10 ** 18; // 5m
    uint256 public CaptainCost = 250000 * 10 ** 18; // 250k
    uint256 public lastCaptainUpdate;
    address public CaptainOwner;
    string public Captain = "Welcome Captain";
    mapping(address => uint256) public lastMintValue;
    mapping(address => uint256) public lastMintTime;
    address payable public payMent;
    mapping(address => uint256) public usermint;
    uint256 public publicSalePrice = 0.0005 ether;

    event CaptainUpdated(address indexed user, string message, uint256 newCaptainCost);
    event PrizePoolClaimed(address indexed CaptainOwner, uint256 amount);
    event Log(string func, uint gas);

    modifier maxLength(string memory message) {
        require(bytes(message).length <= 26, "Message must be 26 characters or less");
        _;
    }

    constructor() ERC20("Captain", "Captain") ERC20Capped(maxSupply) {
        payMent = payable(msg.sender);
        _mint(address(this), maxSupply);
        _transfer(address(this), msg.sender, teamSupply);
        CaptainOwner = msg.sender;
    }

    function mintCaptains(uint256 _quantity) external payable {
        require(_quantity <= 20, "Invalid quantity");
        require(block.timestamp >= lastMintTime[msg.sender] + 1 days, "You can only mint once every 24 hours");
        uint256 mintAmount;
        if (lastMintValue[msg.sender] == 0) {
            mintAmount = _quantity *  initialMintAmount;
        } else {
            mintAmount = _quantity *  lastMintValue[msg.sender] / 2;
        }
        require(mintAmount > 0, "Mint amount is too small");
        require(balanceOf(address(this)) - prizePool >= mintAmount, "Not enough CaptainS left to mint");
        uint256 _remainFreeQuantity = 0;

        uint256 _needPayPrice = 0;
        if (_quantity > _remainFreeQuantity) {
            _needPayPrice = (_quantity - _remainFreeQuantity) * publicSalePrice;
        }

        require(msg.value >= _needPayPrice, "Ether is not enough");
        if (msg.value > 0) {
            (bool success,) = payMent.call{value : msg.value}("");
            require(success, "Transfer failed.");
        }

        lastMintValue[msg.sender] = mintAmount;
        lastMintTime[msg.sender] = block.timestamp;
        _transfer(address(this), msg.sender, mintAmount);
        usermint[msg.sender]+=_quantity;
    }

    function setCaptain(string memory message) external maxLength(message) {
        require(bytes(message).length > 0, "Message cannot be empty");
        if (msg.sender != CaptainOwner) {
            require(balanceOf(msg.sender) >= CaptainCost, "Insufficient CaptainS to set Captain");
            IERC20(address(this)).transferFrom(msg.sender, address(this), CaptainCost);
            _burn(address(this), CaptainCost);
            CaptainCost = CaptainCost + (CaptainCost * 5000) / 10000;
        }
        Captain = message;
        CaptainOwner = msg.sender;
        lastCaptainUpdate = block.timestamp;
        emit CaptainUpdated(msg.sender, message, CaptainCost);
    }

    function claimPrizePool() external {
        require(block.timestamp >= lastCaptainUpdate + 7 days, "Prizepool can be claimed if 7 days have passed without a Captain update");
        require(msg.sender == CaptainOwner, "Only the current CaptainOwner can claim the prizepool");
        uint256 claimAmount = prizePool;
        prizePool = 0;
        _transfer(address(this), msg.sender, claimAmount);
        emit PrizePoolClaimed(msg.sender, prizePool);
    }

    function setPublicPrice(uint256 mintprice) external onlyOwner {
        publicSalePrice = mintprice;
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
