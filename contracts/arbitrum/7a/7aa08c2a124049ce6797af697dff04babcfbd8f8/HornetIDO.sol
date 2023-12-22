// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "./IERC20.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {Ownable} from "./Ownable.sol";
import {PaymentSplitter} from "./PaymentSplitter.sol";
import {toWadUnsafe, toDaysWadUnsafe} from "./SignedWadMath.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";

contract HornetIDO is Ownable, ReentrancyGuard, PaymentSplitter {

    using FixedPointMathLib for uint256;
    /// @notice reference to $HRT token
    IERC20  public hornetToken;
    /// @notice wallet used for the ido distribution
    address public IDOWallet;
    /// @notice max sale for the IDO : 75k $HRT
    uint256 public maxSale;
    /// @notice amount of tokens currently sold
    uint256 public currentSale;
    /// @notice public price, will be 30% higher than whitelist price
    uint256 public publicPrice = 0.00085 ether;
    /// @notice whitelist price for the IDO 
    uint256 public whitelistPrice = 0.00065 ether; 
    /// @notice minimum allocation amount : 100$ equivalent 
    uint256 public minAllocation;
    /// @notice minimum allocation amount : 1k$ equivalent 
    uint256 public maxAllocation;
    /// @notice manages the opening of the ido
    bool public isOpen;
    /// @notice timestamp when IDO will open
    uint256 public idoStart;
    /// @notice timestamp when IDO will close
    uint256 public idoClose;

    mapping(address => bool) public isWhitelisted;
    mapping(address => uint256) public amountAllocated;

    modifier onlyWhenOpen () {
        require(isOpen, "HORNET IDO : IDO is closes");
        _;
    }

    modifier onlyForWhitelisted () {
        require(isWhitelisted[msg.sender], "HORNET IDO : Only whitelisted address");
        _;
    }

    event EnterInIDO(address who, uint256 allocation);
    event IDOLaunched(uint256 timestamp);
    event IDOClosed(uint256 timestamp);

    constructor (
        address _hornet, 
        uint256 _maxSale,
        address _IDOWallet,
        uint256 _minAlloc,
        uint256 _maxAlloc,
        address[] memory payees,
        uint256[] memory shares
    )   PaymentSplitter (payees, shares) 
    {
        hornetToken = IERC20(_hornet);
        maxSale = _maxSale;
        IDOWallet = _IDOWallet;
        minAllocation = _minAlloc;
        maxAllocation = _maxAlloc;
    }

    /** BUY LOGIC **/

    function enterIDO (
        uint256 allocation
    ) 
    public 
    payable 
    onlyWhenOpen
    nonReentrant {
        /// safety check, the amount must be in the range
        require (currentSale + allocation <= maxSale, "HORNET IDO : IDO sold out");
        /// if user already bought some $HRT
        if (amountAllocated[msg.sender] > 0) require (allocation + amountAllocated[msg.sender] <= maxAllocation, "HORNET IDO : Max buy exceeded");
        /// if user has not already bought some $HRT
        else require (allocation <= maxAllocation && allocation >= minAllocation, "HORNET IDO : Wrong amount buy");
        /// safety check, the price must be right
        require (msg.value >= allocation.fmul(publicPrice, FixedPointMathLib.WAD), "HORNET IDO : Wrong price");
        
        amountAllocated[msg.sender] += allocation;
        currentSale += allocation;
        
        hornetToken.transferFrom(IDOWallet, msg.sender, allocation);

        emit EnterInIDO(msg.sender, allocation);
    }


    function enterIDOWhitelist (
        uint256 allocation
    ) 
    public 
    payable 
    onlyWhenOpen 
    onlyForWhitelisted 
    nonReentrant {
        /// safety check, the amount must be in the range
        require(currentSale + allocation <= maxSale, "HORNET IDO : IDO sold out");
        /// if user already bought some $HRT
        if (amountAllocated[msg.sender] > 0) require (allocation + amountAllocated[msg.sender] <= maxAllocation, "HORNET IDO : Max buy exceeded");
        /// if user has not already bought some $HRT
        else require (allocation <= maxAllocation && allocation >= minAllocation, "HORNET IDO : Wrong amount buy");
        /// safety check, the price must be right
        require(msg.value >= allocation.fmul(whitelistPrice, FixedPointMathLib.WAD), "HORNET IDO : Wrong price");
        
        amountAllocated[msg.sender] += allocation;
        currentSale += allocation;

        hornetToken.transferFrom(IDOWallet, msg.sender, allocation);

        emit EnterInIDO(msg.sender, allocation);
    }

    /** ONLY OWNER **/

    function openIDO() external onlyOwner {
        /// safety check
        require(!isOpen, "HORNET IDO : IDO already started");

        isOpen = true;
        idoStart = block.timestamp;

        emit IDOLaunched(idoStart);
    }

    function closeIDO() external onlyOwner {
        /// safety check
        require(isOpen, "HORNET IDO : IDO already closed");
        isOpen = false;
        idoClose = block.timestamp;

        emit IDOClosed(idoClose);
    }

    function setMinAllocation(uint256 amount) external onlyOwner {
        require(amount > 0, "HORNET : Wrong amount");
        minAllocation = amount;
    }

    function setMaxAllocation(uint256 amount) external onlyOwner {
        require(amount > minAllocation, "HORNET : Wrong amount");
        maxAllocation = amount;
    }

    function setMaxSale(uint256 amount) external onlyOwner {
        require(maxSale > 0, "HORNET : Wrong amount");
        maxSale = amount;
    }

    function setWhitelist(address[] memory _who, bool value) external onlyOwner {
        for (uint256 i = 0; i < _who.length; i++) {
            isWhitelisted[_who[i]] = value;
        }
    }
    
}
