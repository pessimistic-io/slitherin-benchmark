//SPDX-License-Identifier: MIT

/**                    
 _____ _____ __    _____ _____ _____ 
|   __|  |  |  |  |     |   | |   __|
|__   |     |  |__|  |  | | | |  |  |
|_____|__|__|_____|_____|_|___|_____|
                                     
Website: https://www.shlongcoin.xyz/
Twitter: https://twitter.com/ShlongCoinErc
Telegram: https://t.me/SHLONGCOINETH
**/
pragma solidity ^0.8.16;

import "./Ownable.sol";
import "./SafeMath.sol";
import "./MerkleProof.sol";

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IUniswapV2Router02 {
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (
        uint amountToken,
        uint amountETH,
        uint liquidity
    );
}

contract ShlongPresale is Ownable {
    using SafeMath for uint256;
    bytes32 public merkleRoot;

    bool public isInit;
    bool public isDeposit;
    bool public isRefund;
    bool public isFinish;
    bool public burnTokens = true;
    address public creatorWallet;
    address public teamWallet;
    address public weth;
    uint8 public tokenDecimals = 18;
    uint256 public ethRaised;
    uint256 public percentageRaised;
    uint256 public tokensSold;
    uint256 public claimRound = 0;

    enum SaleStates {
        CLOSED,
        WHITELIST,
        PUBLIC,
        COMPLETE
    }
    SaleStates public saleState;

    struct Pool {
        uint64 startTime;
        uint64 endTime;
        uint256 tokenDeposit;
        uint256 tokensForSale;
        uint256 tokensForLiquidity;
        uint8 liquidityPortion;
        uint256 hardCap;
        uint256 softCap;
        uint256 maxBuy;
        uint256 minBuy;
    }

    IERC20 public tokenInstance;
    IUniswapV2Factory public UniswapV2Factory;
    IUniswapV2Router02 public UniswapV2Router02;
    Pool public pool;

    mapping(address => uint256) public ethContribution;

    struct UserClaims { 
        bool claimedRoundOne;
        bool claimedRoundTwo;
        bool claimedRoundThree;
    }
    mapping(address => UserClaims) public claims;

    /// @notice Verifies the sender is whitelisted
    modifier whitelisted(bytes32[] calldata merkleProof) {
        require(MerkleProof.verify(merkleProof, merkleRoot, _toBytes32(msg.sender)), "User is not whitelisted");
        _;
    }

    modifier onlyActive {
        require(block.timestamp >= pool.startTime, "Sale must be active.");
        require(block.timestamp <= pool.endTime, "Sale finished.");
        _;
    }

    modifier onlyInactive {
        require(
            block.timestamp < pool.startTime ||
            block.timestamp > pool.endTime ||
            ethRaised >= pool.hardCap, "Sale must be inactive."
            );
        _;
    }

    modifier onlyRefund {
        require(
            isRefund == true ||
            (block.timestamp > pool.endTime && ethRaised < pool.softCap), "Refund unavailable."
            );
        _;
    }

    constructor(
        IERC20 _tokenInstance,
        address _uniswapv2Router,
        address _uniswapv2Factory,
        address _teamWallet,
        address _weth
    ) {

        require(_uniswapv2Router != address(0), "Invalid router address");
        require(_uniswapv2Factory != address(0), "Invalid factory address");

        isInit = false;
        isDeposit = false;
        isFinish = false;
        isRefund = false;
        ethRaised = 0;

        teamWallet = _teamWallet;
        weth = _weth;
        tokenInstance = _tokenInstance;
        creatorWallet = address(payable(msg.sender));
        UniswapV2Router02 = IUniswapV2Router02(_uniswapv2Router);
        UniswapV2Factory = IUniswapV2Factory(_uniswapv2Factory);

        require(UniswapV2Factory.getPair(address(tokenInstance), weth) == address(0), "IUniswap: Pool exists.");

        tokenInstance.approve(_uniswapv2Router, tokenInstance.totalSupply());
    }

    event Liquified(
        address indexed _token,
        address indexed _router,
        address indexed _pair
        );

    event Canceled(
        address indexed _inititator,
        address indexed _token,
        address indexed _presale
        );

    event Bought(address indexed _buyer, uint256 _tokenAmount);

    event Refunded(address indexed _refunder, uint256 _tokenAmount);

    event Deposited(address indexed _initiator, uint256 _totalDeposit);

    event Claimed(address indexed _participent, uint256 _tokenAmount, uint256 _claimPercentage);

    event RefundedRemainder(address indexed _initiator, uint256 _amount);

    event BurntRemainder(address indexed _initiator, uint256 _amount);

    event Withdraw(address indexed _creator, uint256 _amount);

    event SaleStateChanged(SaleStates _saleState);

    event ClaimRoundChanged(uint256 _claimRound);

    /*
    * Reverts ethers sent to this address whenever requirements are not met
    */
    receive() external payable {
        if(block.timestamp >= pool.startTime && block.timestamp <= pool.endTime){
            buyTokens(_msgSender());
        } else {
            revert("Presale is closed");
        }
    }

    /*
    * Initiates the arguments of the sale
    @dev arguments must be pa   ssed in wei (amount*10**18)
    */
    function initSale(
        uint64 _startTime,
        uint64 _endTime,
        uint256 _tokenDeposit,
        uint256 _tokensForSale,
        uint256 _tokensForLiquidity,
        uint8 _liquidityPortion,
        uint256 _hardCap,
        uint256 _softCap,
        uint256 _maxBuy,
        uint256 _minBuy
        ) external onlyOwner onlyInactive {

        require(isInit == false, "Sale already initialized");
        require(_startTime >= block.timestamp, "Invalid start time.");
        require(_endTime > block.timestamp, "Invalid end time.");
        require(_tokenDeposit > 0, "Invalid token deposit.");
        require(_tokensForSale < _tokenDeposit, "Invalid tokens for sale.");
        require(_tokensForLiquidity < _tokenDeposit, "Invalid tokens for liquidity.");
        require(_softCap >= _hardCap / 2, "SC must be >= HC/2.");
        require(_liquidityPortion >= 50, "Liquidity must be >=50.");
        require(_liquidityPortion <= 100, "Invalid liquidity.");
        require(_minBuy < _maxBuy, "Min buy must greater than max.");
        require(_minBuy > 0, "Min buy must exceed 0.");

        Pool memory newPool = Pool(
            _startTime,
            _endTime,
            _tokenDeposit,
            _tokensForSale,
            _tokensForLiquidity,
            _liquidityPortion,
            _hardCap,
            _softCap,
            _maxBuy,
            _minBuy
        );

        pool = newPool;

        isInit = true;
        saleState = SaleStates.WHITELIST;
    }

    /*
    * Once called the owner deposits tokens into pool
    */
    function deposit() external onlyOwner {
        require(!isDeposit, "Tokens already deposited.");
        require(isInit, "Not initialized yet.");

        uint256 totalDeposit = _getTokenDeposit();

        isDeposit = true;

        require(tokenInstance.transferFrom(msg.sender, address(this), totalDeposit), "Deposit failed.");

        emit Deposited(msg.sender, totalDeposit);
    }

    /*
    * Finish the sale - Create Uniswap v2 pair, add liquidity, take fees, withrdawal funds, burn/refund unused tokens
    */
    function finishSale() external onlyOwner onlyInactive{
        require(ethRaised >= pool.softCap, "Soft Cap is not met.");
        require(block.timestamp > pool.startTime, "Can not finish before start");
        require(!isFinish, "Sale already launched.");
        require(!isRefund, "Refund process.");

        percentageRaised = _getPercentageFromValue(ethRaised, pool.hardCap);
        tokensSold = _getValueFromPercentage(percentageRaised, pool.tokensForSale);
        uint256 tokensForLiquidity = _getValueFromPercentage(percentageRaised, pool.tokensForLiquidity);
        isFinish = true;

        //add liquidity
        (uint amountToken, uint amountETH, ) = UniswapV2Router02.addLiquidityETH{value : _getLiquidityEth()}(
            address(tokenInstance),
            tokensForLiquidity,
            tokensForLiquidity,
            _getLiquidityEth(),
            owner(),
            block.timestamp + 600
        );

        require(amountToken == tokensForLiquidity && amountETH == _getLiquidityEth(), "Providing liquidity failed.");

        emit Liquified(
            address(tokenInstance),
            address(UniswapV2Router02),
            UniswapV2Factory.getPair(address(tokenInstance), weth)
        );

        //withrawal eth
        uint256 ownerShareEth = _getOwnerEth();

        if (ownerShareEth > 0) {
            payable(creatorWallet).transfer(ownerShareEth);
        }

        //If HC is not reached, burn or refund the remainder
        if (ethRaised < pool.hardCap) {
            uint256 remainder = _getUserTokens(pool.hardCap - ethRaised) + (pool.tokensForLiquidity - tokensForLiquidity);
            if(burnTokens == true){
                require(tokenInstance.transfer(
                    0x000000000000000000000000000000000000dEaD,
                    remainder), "Unable to burn."
                );
                emit BurntRemainder(msg.sender, remainder);
            } else {
                require(tokenInstance.transfer(creatorWallet, remainder), "Refund failed.");
                emit RefundedRemainder(msg.sender, remainder);
            }
        }

        saleState = SaleStates.COMPLETE;
    }

    /*
    * The owner can decide to close the sale if it is still active
    NOTE: Creator may call this function even if the Hard Cap is reached, to prevent it use:
     require(ethRaised < pool.hardCap)
    */
    function cancelSale() external onlyOwner onlyActive {
        require(!isFinish, "Sale finished.");
        pool.endTime = 0;
        isRefund = true;
        saleState = SaleStates.COMPLETE;

        if (tokenInstance.balanceOf(address(this)) > 0) {
            uint256 tokenDeposit = _getTokenDeposit();
            tokenInstance.transfer(msg.sender, tokenDeposit);
            emit Withdraw(msg.sender, tokenDeposit);
        }
        emit Canceled(msg.sender, address(tokenInstance), address(this));
    }

    /*
    * Allows participents to claim the tokens they purchased
    */
    function claimTokens() external onlyInactive {
        require(isFinish, "Sale is still active.");
        require(!isRefund, "Refund process.");
        require(claimRound > 0, "Claiming is not open.");
        require(claimRound < 4, "Claiming has finished.");

        uint256 claimPercentage = _getClaimPercentage(msg.sender);
        uint256 tokensAmount = _getValueFromPercentage(claimPercentage, _getUserTokens(ethContribution[msg.sender]));
        
        if (claimRound == 1){ 
            claims[msg.sender].claimedRoundOne = true;
        } else if (claimRound == 2){
            claims[msg.sender].claimedRoundOne = true;
            claims[msg.sender].claimedRoundTwo = true;
        } else if (claimRound == 3){
            claims[msg.sender].claimedRoundOne = true;
            claims[msg.sender].claimedRoundTwo = true;
            claims[msg.sender].claimedRoundThree = true;
            ethContribution[msg.sender] = 0;
        }

        require(tokenInstance.transfer(msg.sender, tokensAmount), "Claim failed.");
        emit Claimed(msg.sender, tokensAmount, claimPercentage);
    }
    /*
    * Refunds the Eth to participents
    */
    function refund() external onlyInactive onlyRefund {
        uint256 refundAmount = ethContribution[msg.sender];

        require(refundAmount > 0, "No refund amount");
        require(address(this).balance >= refundAmount, "No amount available");

        ethContribution[msg.sender] = 0;
        address payable refunder = payable(msg.sender);
        refunder.transfer(refundAmount);
        emit Refunded(refunder, refundAmount);
    }

    /*
    * Withdrawal tokens on refund
    */
    function withrawTokens() external onlyOwner onlyInactive onlyRefund {
        if (tokenInstance.balanceOf(address(this)) > 0) {
            uint256 tokenDeposit = _getTokenDeposit();
            require(tokenInstance.transfer(msg.sender, tokenDeposit), "Withdraw failed.");
            emit Withdraw(msg.sender, tokenDeposit);
        }
    }

    /*
    * If requirements are passed, updates user"s token balance based on their eth contribution
    */
    function buyTokensWhitelist(bytes32[] calldata merkleProof) public payable onlyActive checkState(SaleStates.WHITELIST) whitelisted(merkleProof) {
        require(isDeposit, "Tokens not deposited.");
        require(msg.value != 0, "Wei Amount is 0");
        require(msg.value >= pool.minBuy, "Min buy is not met.");
        require(msg.value + ethContribution[msg.sender] <= pool.maxBuy, "Max buy limit exceeded.");
        require(ethRaised + msg.value <= pool.hardCap, "HC Reached.");
        ethRaised += msg.value;
        ethContribution[msg.sender] += msg.value;
    }

        /*
    * If requirements are passed, updates user"s token balance based on their eth contribution
    */
    function buyTokens(address _contributor) public payable onlyActive checkState(SaleStates.PUBLIC) {
        require(isDeposit, "Tokens not deposited.");
        require(_contributor != address(0), "Transfer to 0 address.");
        require(msg.value != 0, "Wei Amount is 0");
        require(msg.value >= pool.minBuy, "Min buy is not met.");
        require(msg.value + ethContribution[_contributor] <= pool.maxBuy, "Max buy limit exceeded.");
        require(ethRaised + msg.value <= pool.hardCap, "HC Reached.");

        ethRaised += msg.value;
        ethContribution[msg.sender] += msg.value;
    }

    /// @notice Function used to change the current `saleState` value.
    /// @param newSaleState The new `saleState` value.
    function setSaleState(uint256 newSaleState) external onlyOwner {
        saleState = SaleStates(newSaleState);
        emit SaleStateChanged(saleState);
    }

    /// @notice Function used to change the current `claimRound` value.
    /// @param newClaimRound The new `saleState` value.
    function setClaimRound(uint256 newClaimRound) external onlyOwner {
        claimRound = newClaimRound;
        emit ClaimRoundChanged(claimRound);
    }

    /// @notice Verifies the current state.
    /// @param saleState_ Sale state to verify. 
    modifier checkState(SaleStates saleState_) {
        require(saleState == saleState_, "Invalid sale state");
        _;
    }

    /*
    * Internal functions, called when calculating balances
    */
    function _getUserTokens(uint256 _amount) internal view returns (uint256) {
        return _amount.mul(tokensSold).div(ethRaised);
    }

    function _getLiquidityEth() internal view returns (uint256) {
        return _getValueFromPercentage(pool.liquidityPortion, ethRaised);
    }

    function _getOwnerEth() internal view returns (uint256) {
        uint256 liquidityEthFee = _getLiquidityEth();
        return ethRaised - liquidityEthFee;
    }

    function _getTokenDeposit() internal view returns (uint256){
        return pool.tokenDeposit;
    }

    function _getPercentageFromValue(uint256 currentValue, uint256 maxValue) private pure returns (uint256) {
        require(currentValue <= maxValue, "Number too high");

        return currentValue.mul(100).div(maxValue);
    }

    function _getValueFromPercentage(uint256 currentPercentage, uint256 maxValue) private pure returns (uint256) {
        require(currentPercentage <= 100, "Number too high");
        return maxValue.mul(currentPercentage).div(100);
    }

    function _getClaimPercentage(address claimer) private view returns (uint256) {
        uint256 claimPercentage = 0;
        if (!claims[claimer].claimedRoundOne){
            claimPercentage += 50;
        }
        if (claimRound == 1) return claimPercentage;

        if (!claims[claimer].claimedRoundTwo){
            claimPercentage += 25;
        }
        if (claimRound == 2) return claimPercentage;

        if (!claims[claimer].claimedRoundThree){
            claimPercentage += 25;
        }
        return claimPercentage;
    }

    function _toBytes32(address addr) pure internal returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    /// @notice Function used to set new merkle root
    /// @param _merkleRoot Newly intended `merkleRoot` value.
    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
       merkleRoot = _merkleRoot;
    }
}

