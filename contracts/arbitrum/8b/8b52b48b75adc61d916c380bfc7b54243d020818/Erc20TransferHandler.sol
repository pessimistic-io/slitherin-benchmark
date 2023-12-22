// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20Metadata} from "./IERC20Metadata.sol";
import {ArcBaseWithRainbowRoad} from "./ArcBaseWithRainbowRoad.sol";
import {IHandler} from "./IHandler.sol";
import {IFeeCollectorFactory} from "./IFeeCollectorFactory.sol";
import {IFeeCollector} from "./IFeeCollector.sol";

/**
 * ERC20 Transfer Handler
 */
contract Erc20TransferHandler is ArcBaseWithRainbowRoad, IHandler
{
    using SafeERC20 for IERC20;
    
    bool public chargeTxFee;
    uint256 public txFeeRate;
    uint256 public bribeFeeRate;
    uint256 public constant MAX_TX_FEE_RATE = 200; // 20%
    uint256 public constant MAX_BRIBE_FEE_RATE = 1000; // 100%
    uint256 public constant MAX_FEE_ON_TRANSFER_PCT_RATE = 1000; // 100%
    address public bribeCollector;
    IFeeCollectorFactory public feeCollectorFactory;
    mapping(string => address) public feeCollectors;
    mapping(string => uint256) public feeOnTransferFlatRate;
    mapping(string => uint256) public feeOnTransferPercentageRate;
    
    constructor(address _rainbowRoad, address _feeCollectorFactory) ArcBaseWithRainbowRoad(_rainbowRoad)
    {
        require(_feeCollectorFactory != address(0), 'Fee Collector Factory cannot be zero address');
        
        chargeTxFee = true;
        txFeeRate = 25; // 25 bps = 2.5%
        bribeFeeRate = 300; // 300 bps = 30%
        bribeCollector = 0x1d9E69A851b2c439A964d8dc3d611781440fd658;
        feeCollectorFactory = IFeeCollectorFactory(_feeCollectorFactory);
    }
    
    function enableTxFeeCharge() external onlyOwner
    {
        require(!chargeTxFee, 'Charge tx fee is enabled');
        chargeTxFee = true;
    }
    
    function disableTxFeeCharge() external onlyOwner
    {
        require(chargeTxFee, 'Charge tx fee is disabled');
        chargeTxFee = false;
    }
    
    function setTxFeeRate(uint256 _txFeeRate) external {
        require(rainbowRoad.feeManagers(msg.sender), 'Invalid fee manager');
        require(_txFeeRate <= MAX_TX_FEE_RATE, 'Tx fee rate too high');
        txFeeRate = _txFeeRate;
    }
    
    function setBribeFeeRate(uint256 _bribeFeeRate) external {
        require(rainbowRoad.feeManagers(msg.sender), 'Invalid fee manager');
        require(_bribeFeeRate <= MAX_BRIBE_FEE_RATE, 'Bribe fee rate too high');
        bribeFeeRate = _bribeFeeRate;
    }
    
    function setFeeOnTransferFlatRate(string calldata tokenSymbol, uint256 _feeOnTransferFlatRate) external {
        require(rainbowRoad.feeManagers(msg.sender), 'Invalid fee manager');
        
        address tokenAddress = rainbowRoad.tokens(tokenSymbol);
        require(tokenAddress != address(0), 'Token must be whitelisted');
        require(!rainbowRoad.blockedTokens(tokenAddress), 'Token is blocked');
        feeOnTransferFlatRate[tokenSymbol] = _feeOnTransferFlatRate;
    }
    
    function setFeeOnTransferPercentageRate(string calldata tokenSymbol, uint256 _feeOnTransferPercentageRate) external {
        require(rainbowRoad.feeManagers(msg.sender), 'Invalid fee manager');
        
        address tokenAddress = rainbowRoad.tokens(tokenSymbol);
        require(tokenAddress != address(0), 'Token must be whitelisted');
        require(!rainbowRoad.blockedTokens(tokenAddress), 'Token is blocked');
        require(_feeOnTransferPercentageRate <= MAX_FEE_ON_TRANSFER_PCT_RATE, 'Fee on transfer rate too high');
        feeOnTransferPercentageRate[tokenSymbol] = _feeOnTransferPercentageRate;
    }
    
    function setBribeCollector(address _bribeCollector) external onlyOwner {
        bribeCollector = _bribeCollector;
    }
    
    function setFeeCollectorFactory(address _feeCollectorFactory) external onlyOwner
    {
        require(_feeCollectorFactory != address(0), 'Fee Collector Factory cannot be zero address');
        feeCollectorFactory = IFeeCollectorFactory(_feeCollectorFactory);
    }
    
    function setFeeCollector(string calldata tokenSymbol, address feeCollectorAddress) external onlyOwner
    {
        address tokenAddress = rainbowRoad.tokens(tokenSymbol);
        require(tokenAddress != address(0), 'Token must be whitelisted');
        require(!rainbowRoad.blockedTokens(tokenAddress), 'Token is blocked');
        require(feeCollectorAddress != address(0), 'Fee collector cannot be zero address');
        
        feeCollectors[tokenSymbol] = feeCollectorAddress;
    }
    
    function encodePayload(string calldata tokenSymbol, uint256 amount) view external returns (bytes memory payload)
    {
        address tokenAddress = rainbowRoad.tokens(tokenSymbol);
        require(tokenAddress != address(0), 'Token must be whitelisted');
        require(!rainbowRoad.blockedTokens(tokenAddress), 'Token is blocked');
        require(amount > 0, 'Invalid amount');
        
        uint256 amountToSend = amount;
        
        if(feeOnTransferPercentageRate[tokenSymbol] > 0) {
            uint256 transferFee = (feeOnTransferPercentageRate[tokenSymbol] * amount) / 1000;
            require(amountToSend > transferFee, 'Insufficient amount to send : Percent Rate');
            amountToSend = amountToSend - transferFee;
        }
        
        if(feeOnTransferFlatRate[tokenSymbol] > 0) {
            require(amountToSend > feeOnTransferFlatRate[tokenSymbol], 'Insufficient amount to send : Flat Rate');
            amountToSend = amountToSend - feeOnTransferFlatRate[tokenSymbol];
        }
        
        return abi.encode(tokenSymbol, amountToSend, amount - amountToSend);
    }
    
    function handleReceive(address target, bytes calldata payload) external onlyRainbowRoad whenNotPaused nonReentrant
    {
        (string memory tokenSymbol, uint256 amount) = abi.decode(payload, (string, uint256));
        require(amount > 0, 'Invalid amount');
        
        address tokenAddress = rainbowRoad.tokens(tokenSymbol);
        require(tokenAddress != address(0), 'Token must be whitelisted');
        require(!rainbowRoad.blockedTokens(tokenAddress), 'Token is blocked');
        
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(address(this)) >= amount, 'Insufficient funds for transfer');
        
        uint256 txFee = 0;
        if(chargeTxFee) {
            txFee = (txFeeRate * amount) / 1000;
            uint256 bribeFee = (bribeFeeRate * txFee) / 1000;
            uint256 lpFee = txFee - bribeFee;
            
            if(bribeFee > 0) {
                token.safeTransfer(bribeCollector, bribeFee);
            }
            
            if(feeCollectors[tokenSymbol] == address(0)) {
                feeCollectors[tokenSymbol] = feeCollectorFactory.createFeeCollector(address(rainbowRoad), address(this));
            }
            
            if(lpFee > 0) {
                token.approve(feeCollectors[tokenSymbol], lpFee);
                IFeeCollector(feeCollectors[tokenSymbol]).notifyRewardAmount(tokenAddress, lpFee);
            }
        }
        
        token.safeTransfer(target, amount - txFee);
    }
    
    function handleSend(address target, bytes calldata payload) external onlyRainbowRoad whenNotPaused nonReentrant
    {
        (string memory tokenSymbol, uint256 amount, uint256 feeOnTransferAmount) = abi.decode(payload, (string, uint256, uint256));
        require(amount > 0, 'Invalid amount');
        address tokenAddress = rainbowRoad.tokens(tokenSymbol);
        require(tokenAddress != address(0), 'Token must be whitelisted');
        require(!rainbowRoad.blockedTokens(tokenAddress), 'Token is blocked');
        
        uint256 feeOnTransfer = feeOnTransferAmount;
        
        if(feeOnTransferPercentageRate[tokenSymbol] > 0) {
            uint256 transferFee = (feeOnTransferPercentageRate[tokenSymbol] * (amount + feeOnTransferAmount)) / 1000;
            require(feeOnTransfer >= transferFee, 'Insufficient amount to send : Percent Rate');
            feeOnTransfer = feeOnTransfer - transferFee;
        }
        
        if(feeOnTransferFlatRate[tokenSymbol] > 0) {
            require(feeOnTransfer >= feeOnTransferFlatRate[tokenSymbol], 'Insufficient amount to send : Flat Rate');
            feeOnTransfer = feeOnTransfer - feeOnTransferFlatRate[tokenSymbol];
        }
        
        require(feeOnTransfer == 0, 'Invalid fee on transfer amount');
        
        uint256 amountToSend = amount + feeOnTransferAmount;
        
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(target) >= amountToSend, 'Target has insufficient balance for transfer');
        uint256 preTransferBalance = token.balanceOf(address(this));
        token.safeTransferFrom(target, address(this), amountToSend);
        uint256 postTransferBalance = token.balanceOf(address(this));
        uint256 diffTransferBalance = postTransferBalance - preTransferBalance;
        require(diffTransferBalance >= amount, 'Invalid transfer amount');
    }
    
    function deposit(address tokenAddress, uint256 amount) external nonReentrant
    {
        require(amount > 0, 'Invalid amount');
        require(tokenAddress != address(0), 'Token address cannot be zero address');
        require(!rainbowRoad.blockedTokens(tokenAddress), 'Token is blocked');
        
        string memory tokenSymbol = IERC20Metadata(tokenAddress).symbol();
        require(rainbowRoad.tokens(tokenSymbol) != address(0), 'Token must be whitelisted');
        
        if(feeCollectors[tokenSymbol] == address(0)) {
            feeCollectors[tokenSymbol] = feeCollectorFactory.createFeeCollector(address(rainbowRoad), address(this));
        }
        
        IERC20 token = IERC20(tokenAddress);
        uint256 preDepositBalance = token.balanceOf(address(this));
        token.safeTransferFrom(msg.sender, address(this), amount);
        uint256 postDepositBalance = token.balanceOf(address(this));
        uint256 diffDepositBalance = postDepositBalance - preDepositBalance;
        
        IFeeCollector(feeCollectors[tokenSymbol]).deposit(msg.sender, diffDepositBalance);
    }
    
    function withdraw(address tokenAddress, uint256 amount) external nonReentrant
    {
        require(amount > 0, 'Invalid amount');
        require(tokenAddress != address(0), 'Token address cannot be zero address');
        require(!rainbowRoad.blockedTokens(tokenAddress), 'Token is blocked');
        
        string memory tokenSymbol = IERC20Metadata(tokenAddress).symbol();
        require(rainbowRoad.tokens(tokenSymbol) != address(0), 'Token must be whitelisted');
        require(feeCollectors[tokenSymbol] != address(0), 'No fee collector found');
       
        IERC20 token = IERC20(tokenAddress);
        require(token.balanceOf(address(this)) >= amount, 'Insufficient liquidity for withdrawal');
        
        IFeeCollector feeCollector = IFeeCollector(feeCollectors[tokenSymbol]);
        require(feeCollector.balanceOf(msg.sender) >= amount, 'Insufficient account balance for withdrawal');
        feeCollector.withdraw(msg.sender, amount);
        token.safeTransfer(msg.sender, amount);
    }
}
