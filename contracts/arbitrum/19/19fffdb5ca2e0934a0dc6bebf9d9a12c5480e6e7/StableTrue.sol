// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "./ISwapRouter.sol";
import "./TransferHelper.sol";

interface IWETH {
    function deposit() external payable;
    function withdrawTo(address, uint256) external;
    function balanceOf(address account) external view returns (uint256);
}

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundID,
        uint256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

contract StableTrue {
    
    IWETH private weth;

    string public name     = "Stable&True";
    string public symbol   = "ST";
    uint8  public decimals = 18;

    uint256 public totalSupply;
    uint256 public minPurchase = 5000000000000000;
    uint256 public managementFunds;
    address public referenceCurrency;
    address public referenceCurrencyPool = 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612;

    address public owner;
    address[] private managementAddresses;

    address public constant routerAddress = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    ISwapRouter public immutable swapRouter = ISwapRouter(routerAddress);

    event  Approval(address indexed src, address indexed guy, uint wad);
    event  Transfer(address indexed src, address indexed dst, uint wad);
    event  Mint(address indexed dst, uint wad);
    event  Withdrawal(address indexed src, uint wad);
    event  ManagementWithdrawal(address indexed src, uint wad);


    mapping (address => uint)                       public  balanceOf;
    mapping (address => mapping (address => uint))  public  allowance;

    Token[] public tokens;

    struct Token {
        address tokenAddress;
        address poolAddress;
        uint24 poolFee;
        uint8 decimals;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    modifier onlyManagementAddress() {
        require(isManagementAddress(msg.sender), "Function can only be called from the management addresses");
        _;
    }

    constructor(address[] memory _tokenAddresses, address[] memory _poolAddresses, uint24[] memory _poolFee, uint8[] memory _decimals) {
        require(_tokenAddresses.length == _poolAddresses.length && _tokenAddresses.length == _poolFee.length && _tokenAddresses.length == _decimals.length);
        owner = msg.sender;
        managementAddresses.push(owner);
        weth = IWETH(_tokenAddresses[0]);
        referenceCurrency = _tokenAddresses[0];
        
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            tokens.push(Token(_tokenAddresses[i], _poolAddresses[i], _poolFee[i], _decimals[i]));
        }

        //tokens.push(Token(WETHAddress, 0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612, 0, 18)); //WETH
        //tokens.push(Token(WBTCAddress, 0x6ce185860a4963106506C203335A2910413708e9, 500, 8)); //WBTC
        //tokens.push(Token(WBTCAddress, 0x6ce185860a4963106506C203335A2910413708e9, 500, 8)); //GMX
    }

    /* Management */

    function isManagementAddress(address addr) private view returns (bool) {
        for (uint256 i = 0; i < managementAddresses.length; i++) {
            if (addr == managementAddresses[i]) {
                return true;
            }
        }
        return false;
    }

    function setManagementAddresses(address[] memory addresses) external onlyOwner {
        managementAddresses = addresses;
    }

    function addManagementAddress(address addr) external onlyOwner {
        managementAddresses.push(addr);
    }

    function removeManagementAddress(address addr) external onlyOwner {
        for (uint256 i = 0; i < managementAddresses.length; i++) {
            if (addr == managementAddresses[i]) {
                managementAddresses[i] = managementAddresses[managementAddresses.length - 1];
                managementAddresses.pop();
                break;
            }
        }
    }

    function updateMinPurchaseValue(uint256 newValue) public onlyManagementAddress {
        minPurchase = newValue;
    }

    function withdrawManagementFunds() public onlyManagementAddress {
        require(managementFunds > 0, "Insufficient balance");
        uint256 withdrawFunds = managementFunds;
        managementFunds = 0;
        weth.withdrawTo(msg.sender, withdrawFunds);
        emit ManagementWithdrawal(msg.sender, withdrawFunds);
    }

    function addToken(address tokenAddress, address poolAddress, uint24 poolFee, uint8 _decimals) public onlyManagementAddress {
        tokens.push(Token(tokenAddress, poolAddress, poolFee, _decimals)); //pool fee 3000 == 0.3% and is relative to ETH-token Pool
    }

    function removeToken(address tokenAddress) public onlyManagementAddress {
        uint256 tokenLen = tokens.length;
        for (uint256 i = 0; i < tokenLen; i++) {
            if (tokens[i].tokenAddress == tokenAddress) {
                tokens[i] = tokens[tokenLen - 1];
                tokens.pop();
                break;
            }
        }
    }

    function updateReferenceCurrency(address newValue) public onlyManagementAddress {
        referenceCurrency = newValue;
    }

    /* User Functions */

    /* Turns ETH to WETH that is trapped in contract so that it enters the contract operations again
       (THIS IS NOT A RESCUE FUNCTION)
    */
    function wrapETH() public {
        weth.deposit{value: address(this).balance}();
    }

    function mint() public payable {
        require(msg.value > minPurchase, "Mint at least enough to cover the gas cost");
        uint256 currentTokenValue = tokenCost();
        weth.deposit{value: msg.value}();
        balanceOf[msg.sender] += (msg.value*10**decimals)/currentTokenValue;
        totalSupply += (msg.value*10**decimals)/currentTokenValue;
        emit Mint(msg.sender, msg.value);
    }

    // TODO: make work for unbalanced sets
    // maxSlippage 100 == 1%
    function withdraw(uint256 value, uint256 maxSlippage) public {
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
        uint256 amount = (value*tokenCost())/10**decimals;
        uint256 returnAmount = 0;
        uint256 referenceCurrencyValue = getLatestPrice(referenceCurrencyPool);

        for (uint256 i = 0; i < tokens.length; i++) {
            
            if(tokens[i].tokenAddress == referenceCurrency){
                uint256 tokenInAmount = (value*(getTokenBalance(tokens[i].tokenAddress)-managementFunds))/totalSupply;
                returnAmount += tokenInAmount;
            }
            else{
                uint256 tokenInAmount = (value*getTokenBalance(tokens[i].tokenAddress))/totalSupply;
                if(tokenInAmount == 0){
                    continue;
                }
                uint256 minOutAmount = (tokenInAmount*getLatestPrice(tokens[i].poolAddress)*(10000-maxSlippage))/(referenceCurrencyValue*10000);
                returnAmount += withdrawSwap(tokens[i].tokenAddress, referenceCurrency, tokenInAmount, minOutAmount, tokens[i].poolFee);
            }
        }

        require((weth.balanceOf(address(this)) - managementFunds) >= returnAmount, "Insufficient contract balance");
        require(returnAmount >= (amount*(10000-maxSlippage))/10000, "Slippage too high");
        balanceOf[msg.sender] -= value;
        totalSupply -= value;
        weth.withdrawTo(msg.sender, returnAmount);
        emit Withdrawal(msg.sender, value);
    }

    function getTokenBalance(address tokenAddress) internal view returns (uint256) {
        IERC20 token = IERC20(tokenAddress);
        return token.balanceOf(address(this));
    }

    function tokenCost() public view returns (uint256) {
        if(totalSupply == 0){
            return 10**decimals;
        }
        return ((((getTotalValueInReferenceCurrency()-managementFunds)*10**decimals) / totalSupply));
    }

    function approve(address guy, uint wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint wad)
        public
        returns (bool)
    {
        require(balanceOf[src] >= wad);

        if (src != msg.sender && allowance[src][msg.sender] != 2**256 - 1) {
            require(allowance[src][msg.sender] >= wad);
            allowance[src][msg.sender] -= wad;
        }

        balanceOf[src] -= wad;
        balanceOf[dst] += wad;

        emit Transfer(src, dst, wad);

        return true;
    }

    /* Automated Management */

    function getTotalValueInReferenceCurrency() public view returns (uint256){
        uint256 totalValue = 0;
        uint256 referenceCurrencyValue = getLatestPrice(referenceCurrencyPool);
        for (uint256 i = 0; i < tokens.length; i++) {
            totalValue += (getLatestPrice(tokens[i].poolAddress) * getTokenBalance(tokens[i].tokenAddress) * 10**(decimals - tokens[i].decimals))/referenceCurrencyValue;
        }
        return totalValue;
    }

    function swapExactInputSingle(address tIn, address tOut, uint256 amountIn, uint256 minAmountOut, uint256 minOutInReferenceCurrency, uint24 poolFee) external onlyManagementAddress returns (uint256 amountOut) {
        TransferHelper.safeApprove(tIn, address(swapRouter), amountIn);
        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tIn,
                tokenOut: tOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
        require(amountOut > minAmountOut);
        uint256 extraChange = (minOutInReferenceCurrency * (amountOut - minAmountOut)) / amountOut; // Except for very volatile markets, this will be less than 0.005% of total investment
        returnChangeToManagementFunds(extraChange);
        amountOut -= extraChange;
   }


    function withdrawSwap(address tIn, address tOut, uint256 amountIn, uint256 minAmountOut, uint24 poolFee) internal returns (uint256 amountOut) {

        TransferHelper.safeApprove(tIn, address(swapRouter), amountIn);

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: tIn,
                tokenOut: tOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            });

        amountOut = swapRouter.exactInputSingle(params);
        // No funds sent to management from withdraw swaps
    }

    function returnChangeToManagementFunds(uint256 changeAmount) internal{
        managementFunds += changeAmount; // Spare change sent to management funds
    }

    // Returns the latest price
    function getLatestPrice(address poolAddress) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(poolAddress);
        (, uint256 price, , , ) = priceFeed.latestRoundData();
        return price;
    }
}
