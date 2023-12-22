// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;
import "./Rumi.sol";
// import "./Whitelist.sol";
import "./IRumiToken.sol";
import "./Initializable.sol";
import "./AggregatorV3Interface.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IUniswapV2Router02.sol";
import "./SafeERC20.sol";
import "./IERC20Metadata.sol";
import "./IUniswapV3Pool.sol";
import "./IUniswapV3Factory.sol";
import "./ISwapRouter.sol";
import "./BytesLib.sol";
import "./NonblockingLzAppUpgradeable.sol";


contract RumiPresale is ReentrancyGuardUpgradeable, OwnableUpgradeable, NonblockingLzAppUpgradeable {
    using SafeERC20 for IERC20;
    using BytesLib for bytes;
    // How many token units a buyer gets per wei.
    // The rate is the conversion between wei and the smallest and indivisible token unit.
    uint256 private _RATE;
    
    address private USDC;
    address private DAI;
    address private USDT;
    address private WETH;

    address private PRICE_FEED_USDC;
    address private PRICE_FEED_DAI;
    address private PRICE_FEED_USDT;
    address private PRICE_FEED_WETH;

    uint public PRECISION;
    uint public slippage;

    //  The amount of usd raised
    uint256 public _usdRaised;
    //  The amount of usd withdrawn
    uint256 private _usdcWithdrawn;

    // // When presale ends, nobody will be able to buy tokens from this contract.
    // uint256 public presaleEndsDate = block.timestamp + 30 days; 

    // The minimum purchase (50 usd) in Wei units
    uint256 public minContribLimit = 50e6; 
    // The maximum purchase (150,000 usd) in Wei units
    uint256 public constant maxContribLimit = 150000e6; 

    // mapping(address => bool) public contractsWhiteList;

    //  The token being sold
    IRumiToken private _TOKEN;

    // Crowdsale Stages    

     struct CrowdsaleStage {
        uint128 id; // serial id (1,2,3) used to disable Crowdsale when another is set
        string name;
        uint256 start;        
        uint256 end;
        uint256 amountAvailable;
        uint256 amountBought;
        uint256 presaleAmount;
        uint256 rate; // Price Of Token in USD ex. 0.098 *10**18
        bool isActive;        
    }

    uint128 public activeCrowdSaleStageId;
    bool public crowdSaleActive;

    /// @notice Mapping from token addresses to Chainlink price feeds
    mapping (address=>AggregatorV3Interface) public priceFeeds;

    mapping (uint128 => CrowdsaleStage) public CrowdSaleStages;

    event TokensPurchased(
        address indexed purchaser,
        address indexed beneficiary,
        uint256 weiSent,
        uint256 indexed tokensBought
    );

    /// @notice Address of uniswap v2 and v3 like router used for swaps
    IUniswapV2Router02 public router;
    IUniswapV3Factory internal factory;
    uint16[4] internal uniswapV3Fees; // Fees for uniswap v3 pools (0.01%, 0.05%, 0.3%, 1%)

    ///@return Address of the swapping router
    address public routerV3;

    /****MULTICHAIN PARAMETERS****/    
    // packet type
    uint8 public constant PT_DEPOSIT_TO_REMOTE_CHAIN = 1;
    uint8 public constant DISABLE_CURRENT_CROWDSALE = 0;
    uint8 public constant SET_CROWDSALE_IN_REMOTE_CHAIN = 2;

    mapping(uint16 => bytes) public remotePresaleContracts;
    event DepositToDstChain(address from, uint16 dstChainId, address to, uint amountOut);
    
    // modifier onlyWhitelisted() {
    //     if(!whitelist()){
    //         _;
    //     }else{
    //         require(contractsWhiteList[msg.sender], "You are not whitelisted");
    //         _;
    //     }
    // }

    /// @notice Defend the contract against unwanted callers    
    modifier _defend()  {
        require(
             msg.sender == tx.origin,
            "Access denied for caller"
        );
        _;      
    }

    function initialize(
        uint256 rate_, 
        IRumiToken token_, 
        address[] memory assets_, 
        address[] memory priceFeeds_, 
        address uniswapV2Router_, 
        address uniswapV3Router_ ,
        address lzEndpoint_
        ) external initializer {
        __Ownable_init();
        require(rate_ > 0, "The token rate cannot be 0");
        require(
            address(token_) != address(0),
            "Token address cannot be the zero address"
        );
        crowdSaleActive = true;
        _RATE = rate_;
        _TOKEN = token_;
        activeCrowdSaleStageId = 0;

        USDC = address(assets_[0]);
        DAI = address(assets_[1]);
        USDT = address(assets_[2]);
        WETH = address(assets_[3]);

        PRICE_FEED_USDC = address(priceFeeds_[0]);
        PRICE_FEED_DAI = address(priceFeeds_[1]);
        PRICE_FEED_USDT = address(priceFeeds_[2]);
        PRICE_FEED_WETH = address(priceFeeds_[3]);

        priceFeeds[USDC] = AggregatorV3Interface(PRICE_FEED_USDC);
        priceFeeds[DAI] = AggregatorV3Interface(PRICE_FEED_DAI);
        priceFeeds[USDT] = AggregatorV3Interface(PRICE_FEED_USDT);
        priceFeeds[WETH] = AggregatorV3Interface(PRICE_FEED_WETH);

        router = IUniswapV2Router02(uniswapV2Router_);
        PRECISION = 1e20;
        slippage = PRECISION/10;
        routerV3 = address(uniswapV3Router_);        
        factory = IUniswapV3Factory(ISwapRouter(uniswapV3Router_).factory());
        uniswapV3Fees =[100, 500, 3000, 10000];        
        __LzAppUpgradeable_init_unchained(lzEndpoint_);
    }
   
    function getPrice(address _token) public view returns (uint price) {                
        (, int p,,,) = priceFeeds[_token].latestRoundData();        
        price = uint(p)*10**10;                
    }

    receive() external payable {
        buyTokens(_msgSender());
    }
    // receive() payable external {}

    /**
     * @dev Returns the RATE (price of token) in terms of usd.
     */
    function rate() public view virtual returns (uint256) {
        return _RATE;
    }

    function ethBalance() public view virtual returns (uint256) {
        return address(this).balance;
    }

    function token() public view virtual returns (IERC20Upgradeable) {
        return _TOKEN;
    }

    function buyTokens(
        address beneficiary
    ) public payable virtual nonReentrant _defend returns (bool) {        
        uint256 tokensBought = (msg.value * getPrice(WETH))/(_RATE);         
        _usdRaised += (msg.value * getPrice(WETH))/1e30;        
        _preValidatePurchase(beneficiary, _usdRaised, tokensBought);        
        _TOKEN.transfer(beneficiary, tokensBought);
        swapExactETHForTokensSupportingFeeOnTransferTokens(WETH, msg.value, USDC);
        CrowdSaleStages[activeCrowdSaleStageId].amountAvailable -= tokensBought;
        CrowdSaleStages[activeCrowdSaleStageId].amountBought += tokensBought;
        emit TokensPurchased(
            _msgSender(),
            beneficiary,
            msg.value,
            tokensBought
        );
        return true;
    }

    function buyTokensWithStable(
        uint256 amount,
        address beneficiary,
        uint64 stableIndex
    ) public nonReentrant _defend returns (bool) {        
        uint256 priceInTermsOfUSDC;
        uint256 rateConversion = _RATE;  
        address[] memory stableArray = new address[](3); 
        stableArray[0] = USDC;
        stableArray[1] = DAI;
        stableArray[2] = USDT;              
        IERC20(stableArray[stableIndex]).safeTransferFrom(msg.sender, address(this), amount);        
        priceInTermsOfUSDC = getPrice(stableArray[stableIndex]);                
        rateConversion = (priceInTermsOfUSDC*_RATE)/1e18;     
        uint256 amountToUse = amount*10**12;    
        uint256 amountInUsdc = amount;               
         if(stableArray[stableIndex] == DAI){
            amountToUse = amount;
            amountInUsdc = amount/10**12;                  
        }      
        uint256 tokensBought = ((amountToUse)/(rateConversion))*10**18;                       
        _preValidatePurchase(beneficiary,amountInUsdc,tokensBought);     
        _usdRaised += priceInTermsOfUSDC*amountInUsdc/10**18;                        
        _TOKEN.transfer(beneficiary, tokensBought);        
        if(stableArray[stableIndex] != USDC){                                
            _swapStableUSDC(stableArray[stableIndex], amount);            
        }                        
        CrowdSaleStages[activeCrowdSaleStageId].amountAvailable -= tokensBought;                
        CrowdSaleStages[activeCrowdSaleStageId].amountBought += tokensBought;
        emit TokensPurchased(
            _msgSender(),
            beneficiary,
            amount,
            tokensBought
        );
        return true;
    }

    function forwardFunds(
        uint256 usdcAmount
    ) public virtual onlyOwner returns (bool) {
        uint256 balanceOfUSDC = IERC20(USDC).balanceOf(address(this));
        require(balanceOfUSDC >= usdcAmount, "Insufficient balance");
       _transferUSDC(currentOwner(), usdcAmount);
       _usdcWithdrawn += usdcAmount;
        return true;
    }

    /*NEEDS TO BE CONNECTED TO LAYER ZERO OR NEW FUNCTION FOR CHAIN Bs*/
    function endPresale() public onlyOwner returns (bool) {                
        return _endPresale();
    }


    function _endPresale() internal returns (bool) {
         uint256 endTime = CrowdSaleStages[activeCrowdSaleStageId].end;
        uint256 currentTime  = block.timestamp;       
        require(
          currentTime > endTime,
            "This Crowdsale still ongoing"
        );         
        uint256 allLiquidity = _TOKEN.balanceOf(address(this));
        _TOKEN.transfer(currentOwner(), allLiquidity);       
        _transferEth(payable(currentOwner()), address(this).balance);        
        _transferUSDC(currentOwner(), IERC20(USDC).balanceOf(address(this)));
        CrowdSaleStages[activeCrowdSaleStageId].isActive = false;
        crowdSaleActive = false;
        return true;
    }

    /**
     * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met.
     * Use `super` in contracts that inherit from Crowdsale to extend their validations.
     * Example from CappedCrowdsale.sol's _preValidatePurchase method:
     *     super._preValidatePurchase(beneficiary, weiAmount);
     *     require(weiRaised().add(weiAmount) <= cap);
     * @param beneficiary Address performing the token purchase
     * @param weiSent Value in wei involved in the purchase
     * @param tokensBought Value in wei involved in the purchase
     */
    function _preValidatePurchase(
        address beneficiary,
        uint256 weiSent,
        uint256 tokensBought
    ) private view {        
        require(
            beneficiary != address(0),
            "Beneficiary address cannot be the zero address."
        );
        require(weiSent != 0, "You cannot buy with 0 ETH.");       

        //VALIDATE THIS
        require(
            CrowdSaleStages[activeCrowdSaleStageId].amountAvailable >= tokensBought,
            "Token amount exceeds the presale stage balance."
        );

        require(
            CrowdSaleStages[activeCrowdSaleStageId].isActive == true,
            "Verify stage is active."
        );        

         require(
            crowdSaleActive == true,
            "CrowdSales are not active."
        );

        require(
            _TOKEN.balanceOf(address(this)) >= tokensBought,
            "Token amount exceeds the presale balance."
        );
         require(
            weiSent >= minContribLimit,
            "Token amount less than min conribution."
        );
         require(
            weiSent <= maxContribLimit,
            "Token amount greater than max conribution."
        );
        uint256 startTime = CrowdSaleStages[activeCrowdSaleStageId].start;
        uint256 endTime = CrowdSaleStages[activeCrowdSaleStageId].end;
        uint256 currentTime  = block.timestamp;

        require(
           currentTime >= startTime,
            "Not within Crowdsale start period"
        );
        require(
          currentTime <= endTime,
            "This Crowdsale already finished"
        );         
    }

    function _transferEth(
        address payable beneficiary,
        uint256 weiAmount
    ) private nonReentrant {
        (bool success, bytes memory data) = beneficiary.call{value: weiAmount}(
            ""
        );
        require(success, string(data));
    }

    function _transferUSDC(
        address  beneficiary,
        uint256 amount
    ) private nonReentrant {        
        IERC20(USDC).safeTransfer(beneficiary, amount);
    }

    /**
     * @dev Returns the TKNs balance of presale contract.
     */
    function availableTokens() public view returns (uint256) {
        return _TOKEN.balanceOf(address(this));
    }

    /**    
     * @dev Returns the equivalent TKNs of a ETH amount.
     */
    function quoteTokenInETH(uint256 _amountToBuy) public view returns (uint256) {
        uint256 amountOfETH = (_amountToBuy*_RATE*10**18)/getPrice(WETH);     
        return amountOfETH;
    }

    /**    
     * @dev Returns the equivalent TKNs of a ETH amount.
     */
    function quoteTokenInUSD(uint256 _amountToBuy) public view returns (uint256) {
        uint256 amountOfUSD = (_amountToBuy*_RATE);
        return amountOfUSD;
    }

    /*NEEDS TO BE CONNECTED TO LAYER ZERO OR NEW FUNCTION FOR CHAIN Bs*/
    /**
     * @dev Adds TKN tokens liquidity to presale contract.
     */
    function addLiquidityToPresale(uint256 _amount) public onlyOwner returns (bool) {        
        require(_TOKEN.mintToPresaleContract(_amount), "Add liquidity to presale contract is not allowed anymore");        
        return true;
    }

    /**
     * Returns the balance of an address.
     */
    function balanceOf(address _address) public view returns (uint) {
        return _TOKEN.balanceOf(_address);
    }
    
    function getCrowdsaleStage(uint128 _stage) public view returns (CrowdsaleStage memory stage){
        return CrowdSaleStages[_stage];
    }

    function activateCrowdSaleManually(uint128 _id) public onlyOwner {
        activeCrowdSaleStageId = _id;        
        uint128 j=0;
        for (j = 1; j < _id; j++) {  //for loop example
                 CrowdSaleStages[j].isActive = false;
        }
        _RATE = CrowdSaleStages[_id].rate;
        CrowdSaleStages[_id].isActive = true;                                    
    }

    function setMinimumContribution(uint256 _amount) public onlyOwner{
        minContribLimit = _amount;
    } 
    
    function setCrowdsaleStage(
        uint128 _id,
        string memory _name,
        uint64 _start,   
        uint64 _end,
        uint256 _amountAvailable,        
        uint256 _rate,
        bool _activate
    ) public onlyOwner{
        _setCrowdSaleStage( _id, _name, _start, _end, _amountAvailable, _rate, _activate);
    }

    function _setCrowdSaleStage(
        uint128 _id,
        string memory _name,
        uint64 _start,   
        uint64 _end,
        uint256 _amountAvailable,        
        uint256 _rate,
        bool _activate
        ) internal {
          // CrowdSale Stage can only be set once
        require(CrowdSaleStages[_id].start == 0, "Crowdsale Exists");
               
        //Set new Crowdsale
        CrowdSaleStages[_id] = CrowdsaleStage({
            id: _id,
            name: _name,
            start: _start,
            end: _end,            
            amountAvailable: _amountAvailable,
            amountBought: 0,
            presaleAmount: _amountAvailable,
            isActive: _activate,
            rate: _rate
        });

        //Deactivate other CrowdSales
        if(_activate){
             uint128 j=0;
            for (j = 1; j < _id; j++) {  //for loop example
                 CrowdSaleStages[j].isActive = false;
            }
            //Update new current Rate
            _RATE = _rate;
            activeCrowdSaleStageId = _id;
        }
        
    }

    function modifyCrowdSale(
        uint128 _id,
        string memory _name,
        uint64 _start,   
        uint64 _end,
        uint256 _amountAvailable,        
        uint256 _rate,
        bool _isActive
    ) external onlyOwner {        
        CrowdSaleStages[_id].name = _name;
        CrowdSaleStages[_id].start = _start;
        CrowdSaleStages[_id].end = _end;
        CrowdSaleStages[_id].amountAvailable = _amountAvailable;
        CrowdSaleStages[_id].presaleAmount = _amountAvailable;
        CrowdSaleStages[_id].isActive = _isActive;
        CrowdSaleStages[_id].rate = _rate;
    }

    /**
     * @notice Internal helper function to get the token path needed for swapping with uniswap v2 router
     */
    function _getPathForSwap(address tokenIn, address tokenOut) internal pure returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        return path;
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(address tokenIn, uint amountIn, address tokenOut) internal {
        uint minOut = (getPrice(tokenIn)*amountIn)*(PRECISION-slippage)/(PRECISION*1e30);                
        uint allowance = IERC20(tokenIn).allowance(address(this), address(router));
        if(allowance<amountIn) {
            IERC20(tokenIn).safeIncreaseAllowance(address(router), 2**256-1-allowance);
        }
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountIn}(
            minOut, // accept any amount of Tokens
            _getPathForSwap(tokenIn, tokenOut),
            address(this), // Wallet address to recieve USDC
            block.timestamp
        );       
    }

    /**
     * @notice Swaps the stable asset to USDC
     * @param tokenIn the stable asset to swap for USDC
     */
    function _swapStableUSDC(address tokenIn, uint amountIn) internal {
        address tokenOut = USDC;                
        /*
        bugFix: Previous method for calculating expectedOut was naive and assumed that all tokens
        being swapped here have a price of $1        
        We get the price from the oracle instead
        */          
        uint tokenOutPrice = getPrice(USDC);
        uint tokenInPrice = getPrice(tokenIn);
        uint expectedOut = (amountIn * tokenInPrice) / tokenOutPrice;
        uint minOut = (expectedOut * (PRECISION - slippage)) / PRECISION;        
        minOut = (tokenIn == DAI) ? minOut/10**12 : minOut;
        // Improvement: Use pool with most liquidity rather than pool with lowest fee        
        address poolAddress;
        uint maxAmount;
        for (uint i = 0; i < uniswapV3Fees.length; i++) {
            address poolToConsider = factory.getPool(
                tokenIn,
                USDC,
                uniswapV3Fees[i]
            );                      
            if (amountIn > maxAmount) {
                maxAmount = amountIn;
                poolAddress = poolToConsider;
            }
        }    
        uint allowance = IERC20(tokenIn).allowance(address(this), address(routerV3));        
        if(allowance<amountIn) {
            IERC20(tokenIn).safeIncreaseAllowance(address(routerV3), 2**256-1-allowance);
        }               
        IUniswapV3Pool swapPool = IUniswapV3Pool(poolAddress);              
        ISwapRouter(routerV3).exactInputSingle(
            ISwapRouter.ExactInputSingleParams(
                tokenIn,
                tokenOut,
                swapPool.fee(),
                address(this),
                block.timestamp,
                amountIn,
                minOut,
                0
            )
        );
    }

     //MULTICHAIN --------------------------------------------------------------------------------------------------------

    function setRemotePresaleContract(uint16 _chainId, bytes calldata _presaleContract) external onlyOwner{
        remotePresaleContracts[_chainId] = _presaleContract;
    }

    function estimateSendFee(uint16 _dstChainId, bytes calldata _toAddress, uint _amount, bool _useZro, bytes calldata _adapterParams) public view virtual returns (uint nativeFee, uint zroFee) {
        // mock the payload for sendFrom()
        bytes memory payload = abi.encode(DISABLE_CURRENT_CROWDSALE, _toAddress, _amount, _adapterParams);
        return lzEndpoint.estimateFees(_dstChainId, address(this), payload, _useZro, _adapterParams);
    }


    function _nonblockingLzReceive(uint16 _fromChainId, bytes memory _srcAddress, uint64 _nonce, bytes memory _payload) internal virtual override {
        uint16 packetType;
        assembly {
            packetType := mload(add(_payload, 32))
        }                
        if (packetType == DISABLE_CURRENT_CROWDSALE) {                        
            _endPresale();
        }else if (packetType == SET_CROWDSALE_IN_REMOTE_CHAIN) {                                    
            (,,,,
            uint128 _id,
            string memory _name,
            uint64 _start,
            uint64 _end,
            uint256 _amountAvailable,
            uint256 _rate,
            bool _isActive) = abi.decode(_payload, (uint16, bytes, uint, bytes, uint128, string, uint64, uint64, uint256, uint256, bool));           
            _setCrowdSaleStage(_id, _name, _start, _end, _amountAvailable, _rate, _isActive);
        }  
        else {
            revert("OFTCore: unknown packet type");
        }
    }

    function replenishRumiToDstChain(
        uint16 _dstChainId,
        bytes calldata _toAddress,  
        uint _amount, // amount of token to deposit
        bytes calldata _adapterParams
    ) external _defend payable onlyOwner {
        bytes memory dstStakingContract = remotePresaleContracts[_dstChainId];
        require(keccak256(dstStakingContract) != keccak256(""), "invalid _dstChainId");               
        address to = _toAddress.toAddress(0);       
        _TOKEN.sendFrom{value: address(this).balance}(
            address(this),
            _dstChainId,
            _toAddress,
            _amount,
            payable(msg.sender),
            address(0),
            _adapterParams
        );
        emit DepositToDstChain(msg.sender, _dstChainId, to, _amount);
    }

    function disableCrossChainCrowdSale(
         uint16 _dstChainId, 
        bytes calldata _to,         
        bytes calldata _adapterParams
    ) external _defend payable onlyOwner {
         bytes memory dstStakingContract = remotePresaleContracts[_dstChainId];
            require(keccak256(dstStakingContract) != keccak256(""), "invalid _dstChainId"); 
            bytes memory payload = abi.encode(DISABLE_CURRENT_CROWDSALE, _to, 0, _adapterParams);
            _lzSend(_dstChainId, payload, payable(msg.sender), address(0x0), _adapterParams, msg.value);  
    }

    function setCrossChainCrowdsale(
        uint16 _dstChainId, 
        bytes calldata _to,         
        bytes calldata _adapterParams,
        uint128 _id,
        string memory _name,
        uint64 _start,   
        uint64 _end,
        uint256 _amountAvailable,        
        uint256 _rate,
        bool _isAvailable
    ) external _defend payable onlyOwner {
         bytes memory dstStakingContract = remotePresaleContracts[_dstChainId];
            require(keccak256(dstStakingContract) != keccak256(""), "invalid _dstChainId"); 
            bytes memory payload = abi.encode(SET_CROWDSALE_IN_REMOTE_CHAIN,
             _to, 
             0, 
             _adapterParams,
             _id,
             _name,
             _start,
             _end,
             _amountAvailable,
             _rate,
             _isAvailable);
        _lzSend(_dstChainId, payload, payable(msg.sender), address(0x0), _adapterParams, msg.value);  
    }

    function rescueTokens() public onlyOwner {
        uint256 allLiquidity = _TOKEN.balanceOf(address(this));
        _TOKEN.transfer(currentOwner(), allLiquidity);
    }

    function setToken(IRumiToken token_) public onlyOwner{
        _TOKEN = token_;
    }

    /***************WHITELIST FUNCTIONS***************/

    // /**
    //  * Adds an address to the whitelist of presale contract.
    //  */
    // function addToWhiteList(address _address) public onlyOwner {
    //     contractsWhiteList[_address] = true;
    // }
    
    // /**
    //  * Removes an address from the whitelist of presale contract.
    //  */
    // function removeFromWhiteList(address _address) public onlyOwner {
    //     contractsWhiteList[_address] = false;
    // }

    // /**
    //  * Adds more than one address to the whitelist of presale contract.
    //  */
    // function addManyToWhitelist(address[] memory _addresses) public onlyOwner {
    //     for (uint256 i = 0; i < _addresses.length; i++) {
    //         contractsWhiteList[_addresses[i]] = true;
    //     }
    // }

    // /**
    //  * Enables the whitelist.
    //  */
    // function enableWhitelist() public onlyOwner {
    //     _enableWhitelist();
    // }

    // /**
    //  * Disables the whitelist.
    //  */
    // function disableWhitelist() public onlyOwner {
    //     _disableWhitelist();
    // }

    // /**
    //  * Returns if an address is whitelisted.
    //  */
    // function isWhitelisted(address _address) public view returns (bool) {
    //     return contractsWhiteList[_address];
    // }
}
