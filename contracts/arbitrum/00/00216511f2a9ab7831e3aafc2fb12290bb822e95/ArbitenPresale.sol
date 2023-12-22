pragma solidity ^0.8.0;

import "./ERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

// ArbiTenPresale
contract ArbiTenPresale is Ownable, ReentrancyGuard {
    using SafeERC20 for ERC20;

    address public constant wethAddress = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;

    // Inverse ArbiTen Price
    uint public arbiTenINVSalePriceE35 = 10 * 1e35;
    uint public _10SHAREINVSalePriceE35 = 0.05 * 1e35;

    // 1,000 ArbiTen on offer, for 0.1 ETH each, 100 ETH total raise
    uint public constant ArbiTenMaximumSupply = 1000 * 1e18;
    // 5 10SHARE on offer, 100 ETH total raise
    uint public constant _10SHAREMaximumSupply = 5 * 1e18;

    // 50 ArbiTen per wallet, for 0.1 ETH each, 5 ETH total per wallet
    uint public constant maxArbiTenPurchase = 50 * 1e18;
    // 50 ArbiTen per wallet, for 0.1 ETH each, 5 ETH total per wallet
    uint public constant max10SHAREPurchase = 0.25 * 1e18;

    // We use a counter to defend against people sending ArbiTen back
    uint public ArbiTenRemaining = ArbiTenMaximumSupply;
    uint public _10SHARERemaining = _10SHAREMaximumSupply;

    uint public constant oneDay = 3600 * 24;

    uint public startTime;
    uint public publicEndTime;

    mapping(address => uint) public userArbiTenTally;
    mapping(address => uint) public user10SHARETally;

    bool public hasRetrievedUnsoldPresale = false;

    address public immutable ArbiTenAddress;
    address public immutable _10SHAREAddress;

    address public immutable treasuryAddress;

    event ArbiTenPurchased(address sender, uint ethSpent, uint ArbiTenReceived, uint _10SHAREReceived);
    event StartTimeChanged(uint newStartTime, uint newEndTime);
    event _10SHAREINVSalePriceE35Changed(uint newSalePriceE5);
    event arbitenINVSalePriceE35Changed(uint newSalePriceE5);
    event RetrieveUnclaimedTokens(uint ArbiTenAmount);
    event ArbiTenRecovery(address recipient, uint recoveryAmount);
    event _10SHARERecovery(address recipient, uint recoveryAmount);

    constructor(uint _startTime, address _treasuryAddress, address _ArbiTenAddress, address __10SHAREAddress) {
        require(block.timestamp < _startTime, "cannot set start block in the past!");
        require(_treasuryAddress != _ArbiTenAddress, "_treasuryAddress cannot be equal to _ArbiTenAddress");
        require(_treasuryAddress != address(0), "_ArbiTenAddress cannot be the zero address");
        require(_ArbiTenAddress != address(0), "_ArbiTenAddress cannot be the zero address");
        require(__10SHAREAddress != address(0), "_10SHAREAddress cannot be the zero address");
    
        startTime = _startTime;
        publicEndTime = startTime + oneDay;

        ArbiTenAddress = _ArbiTenAddress;
        _10SHAREAddress = __10SHAREAddress;
        treasuryAddress = _treasuryAddress;
    }

    function buyArbiTen(uint wethToSpend) external payable nonReentrant {
        require(block.timestamp >= startTime, "presale hasn't started yet, good things come to those that wait");
        require(block.timestamp < publicEndTime, "presale has ended, come back next time!");
        require(ArbiTenRemaining > 0, "No more ArbiTen remaining! Come back next time!");
        require(ERC20(ArbiTenAddress).balanceOf(address(this)) > 0, "No more ArbiTen left! Come back next time!");
        require(userArbiTenTally[msg.sender] < maxArbiTenPurchase, "user has already purchased too much ArbiTen");

        require(wethToSpend > 0, "not enough weth provided");

        uint originalArbiTenAmountUnscaled = (wethToSpend * arbiTenINVSalePriceE35) / 1e35;
        uint original10SHAREAmountUnscaled = (wethToSpend * _10SHAREINVSalePriceE35) / 1e35;

        uint wethDecimals = ERC20(wethAddress).decimals();
        uint ArbiTenDecimals = ERC20(ArbiTenAddress).decimals();
        uint _10SHAREDecimals = ERC20(_10SHAREAddress).decimals();

        uint originalArbiTenAmount = wethDecimals == ArbiTenDecimals ?
                                        originalArbiTenAmountUnscaled :
                                            wethDecimals > ArbiTenDecimals ?
                                                originalArbiTenAmountUnscaled / (10 ** (wethDecimals - ArbiTenDecimals)) :
                                                originalArbiTenAmountUnscaled * (10 ** (ArbiTenDecimals - wethDecimals));

        uint original10SHAREAmount = wethDecimals == _10SHAREDecimals ?
                                        original10SHAREAmountUnscaled :
                                            wethDecimals > _10SHAREDecimals ?
                                                original10SHAREAmountUnscaled / (10 ** (wethDecimals - _10SHAREDecimals)) :
                                                original10SHAREAmountUnscaled * (10 ** (_10SHAREDecimals - wethDecimals));

        uint ArbiTenPurchaseAmount = originalArbiTenAmount;
        uint _10SHAREPurchaseAmount = original10SHAREAmount;

        if (userArbiTenTally[msg.sender] + ArbiTenPurchaseAmount > maxArbiTenPurchase)
            ArbiTenPurchaseAmount = maxArbiTenPurchase - userArbiTenTally[msg.sender];

        if (user10SHARETally[msg.sender] + _10SHAREPurchaseAmount > max10SHAREPurchase)
            _10SHAREPurchaseAmount = max10SHAREPurchase - user10SHARETally[msg.sender];


        // if we dont have enough left, give them the rest.
        if (ArbiTenRemaining < ArbiTenPurchaseAmount)
            ArbiTenPurchaseAmount = ArbiTenRemaining;
        if (_10SHARERemaining < _10SHAREPurchaseAmount)
            _10SHAREPurchaseAmount = _10SHARERemaining;

        require(ArbiTenPurchaseAmount > 0, "user cannot purchase 0 ArbiTen");
        require(_10SHAREPurchaseAmount > 0, "user cannot purchase 0 ArbiTen");

        // shouldn't be possible to fail these asserts.
        assert(ArbiTenPurchaseAmount <= ArbiTenRemaining);
        require(ArbiTenPurchaseAmount <= ERC20(ArbiTenAddress).balanceOf(address(this)), "not enough ArbiTen in contract");

        assert(_10SHAREPurchaseAmount <= _10SHARERemaining);
        require(_10SHAREPurchaseAmount <= ERC20(_10SHAREAddress).balanceOf(address(this)), "not enough 10SHARE in contract");

        ERC20(ArbiTenAddress).safeTransfer(msg.sender, ArbiTenPurchaseAmount);
        ERC20(_10SHAREAddress).safeTransfer(msg.sender, _10SHAREPurchaseAmount);

        ArbiTenRemaining = ArbiTenRemaining - ArbiTenPurchaseAmount;
        userArbiTenTally[msg.sender] = userArbiTenTally[msg.sender] + ArbiTenPurchaseAmount;

        _10SHARERemaining = _10SHARERemaining - _10SHAREPurchaseAmount;
        user10SHARETally[msg.sender] = user10SHARETally[msg.sender] + _10SHAREPurchaseAmount;

        uint wethSpent = wethToSpend;
        if (ArbiTenPurchaseAmount < originalArbiTenAmount) {
            wethSpent = (ArbiTenPurchaseAmount * wethToSpend) / originalArbiTenAmount;
        }

        if (wethSpent > 0) {         
            ERC20(wethAddress).safeTransferFrom(msg.sender, treasuryAddress, wethSpent);
        }

        emit ArbiTenPurchased(msg.sender, wethSpent, ArbiTenPurchaseAmount, _10SHAREPurchaseAmount);
    }

    function sendUnclaimedsToTreasuryAddress() external onlyOwner {
        require(block.timestamp > publicEndTime, "presale hasn't ended yet!");
        require(!hasRetrievedUnsoldPresale, "can only recover unsold tokens once!");

        hasRetrievedUnsoldPresale = true;

        uint ArbiTenRemainingBalance = ERC20(ArbiTenAddress).balanceOf(address(this));

        require(ArbiTenRemainingBalance > 0, "no more ArbiTen remaining! you sold out!");

        ERC20(ArbiTenAddress).safeTransfer(treasuryAddress, ArbiTenRemainingBalance);

        emit RetrieveUnclaimedTokens(ArbiTenRemainingBalance);
    }

    function setStartTime(uint _newStartTime) external onlyOwner {
        require(block.timestamp < startTime, "cannot change start block if sale has already commenced");
        require(block.timestamp < _newStartTime, "cannot set start block in the past");

        startTime = _newStartTime;
        publicEndTime = startTime + oneDay;

        emit StartTimeChanged(_newStartTime, publicEndTime);
    }

    function setArbiTenINVSalePriceE35(uint _newArbiTenINVSalePriceE35) external onlyOwner {
        require(block.timestamp < startTime - 3600, "cannot change price 1 hour before start block");
        require(_newArbiTenINVSalePriceE35 >= 1 * 1e35, "new price can't be too low");
        require(_newArbiTenINVSalePriceE35 <= 100 * 1e35, "new price can't be too high");
        arbiTenINVSalePriceE35 = _newArbiTenINVSalePriceE35;

        emit arbitenINVSalePriceE35Changed(arbiTenINVSalePriceE35);
    }

    function set10SHAREINVSalePriceE35(uint _new10SHAREINVSalePriceE35) external onlyOwner {
        require(block.timestamp < startTime - 3600, "cannot change price 1 hour before start block");
        require(_new10SHAREINVSalePriceE35 >= 0.01 * 1e35, "new price can't be too low");
        require(_new10SHAREINVSalePriceE35 <= 10 * 1e35, "new price can't be too high");
        _10SHAREINVSalePriceE35 = _new10SHAREINVSalePriceE35;

        emit _10SHAREINVSalePriceE35Changed(_10SHAREINVSalePriceE35);
    }

    // Recover ArbiTen in case of error, only owner can use.
    function recoverArbiTen(address recipient, uint recoveryAmount) external onlyOwner {
        if (recoveryAmount > 0)
            ERC20(ArbiTenAddress).safeTransfer(recipient, recoveryAmount);
        
        emit ArbiTenRecovery(recipient, recoveryAmount);
    }

    function recover10SHARE(address recipient, uint recoveryAmount) external onlyOwner {
        if (recoveryAmount > 0)
            ERC20(_10SHAREAddress).safeTransfer(recipient, recoveryAmount);
        
        emit _10SHARERecovery(recipient, recoveryAmount);
    }
}
