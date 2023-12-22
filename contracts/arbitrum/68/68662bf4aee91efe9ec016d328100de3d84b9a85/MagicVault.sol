//SPDX-License-Identifier: Unlicense
// Creator: Pixel8 Labs
pragma solidity ^0.8.0;

import "./Signature.sol";
import "./IStargateRouter.sol";
import "./IStargateLPFarming.sol";
import "./ISushiSwapRouter.sol";
import "./ERC20.sol";
import "./ERC20_IERC20.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";

contract MagicVault is ERC20, ReentrancyGuard, Ownable{
    using SafeMath for uint256;

    // @notice Constants used in this contract
    uint256 constant MAX_INT = 2 ** 256 - 1;

    // @notice Stargate contract interfaces & pools info
    IStargateRouter public stargateRouter;
    IStargateLPFarming public stargateLPFarming;

    // @notice SushiSwap contract interfaces
    ISushiSwapRouter public sushiSwapRouter; 

    uint16 public stargatePoolID;
    uint256 public farmingPoolID;

    // @notice Signer address
    address public signer;

    // @notice USDC token interface
    IERC20 public usdc;
    IERC20 public sgLPToken;
    IERC20 public magic;
    IERC20 public stg;

    // Custom Errors
    error ZeroDepositAmount();
    error ZeroWithdrawAmount();
    error ZeroClaimAmount();
    error InvalidSignature();
    error NotEnoughBalance();
    error ZeroWithdrawMAGIC();
    error NotEnoughMAGIC();

    // Events
    event LPTokenMinted(address _to, uint256 _amount);
    event USDCwithdraw(address _to, uint256 _mvlpToken, uint256 _usdc);
    event MAGICCollect(address _to, uint256 _magic);
    event Settle(address _to, uint256 _stg, uint256 _usdc);

    constructor(
        address _routerAddress,
        address _usdcAddress,
        uint16 _poolID,
        address _poolAddress,
        uint256 _farmingPoolId,
        address _lpFarmingAddress,
        address _magicAddress,
        address _signerAddress,
        address _stgAddress,
        address _sushiswapRouterAddress
    ) ERC20("Magic Vault LP Token", "MV-LP") {
        // Setup Stargate Router & LP Farming Interface
        stargateRouter = IStargateRouter(_routerAddress);
        stargateLPFarming = IStargateLPFarming(_lpFarmingAddress);

        // Setup SushiSwap Router Interface
        sushiSwapRouter = ISushiSwapRouter(_sushiswapRouterAddress);

        // Setup USDC Interface & approve USDC to be spent by Stargate Router
        usdc = IERC20(_usdcAddress);
        usdc.approve(_routerAddress, MAX_INT);

        // Setup Stargate Pool ID used to deposit USDC
        stargatePoolID = _poolID;
        farmingPoolID = _farmingPoolId;

        // Setup LP Token Interface & approve LP Token to be spent by Stargate LP Farming contract
        sgLPToken = IERC20(_poolAddress);
        sgLPToken.approve(_lpFarmingAddress, MAX_INT);

        // Setup Magic Interface 
        magic = IERC20(_magicAddress);

        // Setup Signer Address
        signer = _signerAddress;

        // Setup STG Interface
        stg = IERC20(_stgAddress);
        stg.approve(address(sushiSwapRouter), MAX_INT);   
    }

    // @notice MV-LP token will use 6 decimals (stablecoin decimals)
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    // @notice User deposit USDC to earn $MAGIC staking reward
    // @params Amount of USDC to be deposited, input with 6 decimals
    function deposit(uint256 _amountUSDC) public nonReentrant {
        if (_amountUSDC == 0) revert ZeroDepositAmount();

        // Transfer USDC from user to contract
        usdc.transferFrom(msg.sender, address(this), _amountUSDC);

        // Snapshot Stargate LP token balance before add liquidity
		uint256 prevBalance = sgLPToken.balanceOf(address(this));

        // Deposit USDC to Stargate Pool via Stargate Router
        stargateRouter.addLiquidity(stargatePoolID, _amountUSDC, address(this));

        // Snapshot Stargate LP token balance after add liquidity
		uint256 afterBalance = sgLPToken.balanceOf(address(this));

        // Get exact amount of sgLpToken received after adding liquidity
		uint256 sgLPTokenReceived = afterBalance.sub(prevBalance);

        // Mint MV-LP token based on deposited USDC amount
        _mint(msg.sender, sgLPTokenReceived);

        // Deposit LP token to Stargate LP Farming contract
        stargateLPFarming.deposit(farmingPoolID, sgLPTokenReceived);

        emit LPTokenMinted(msg.sender, sgLPTokenReceived);
    }

    function claim(uint256 _amountMAGIC, bytes memory signature) public nonReentrant {
        if(_amountMAGIC == 0) revert ZeroWithdrawAmount();
        
        // Verify signature
        if(Signature.verify(_amountMAGIC, msg.sender, signature) != signer) revert InvalidSignature();
        
        // Transfer $MAGIC from contract to user
        magic.transfer(msg.sender, _amountMAGIC);

        emit MAGICCollect(msg.sender, _amountMAGIC);
    }

    function withdraw(uint256 _amountMVLpToken) public nonReentrant {
        if(_amountMVLpToken == 0) revert ZeroWithdrawAmount();

        if(_amountMVLpToken > balanceOf(msg.sender)) revert NotEnoughBalance();

        // Snapshot Stargate LP token balance before unstake
        uint256 prevBalance = sgLPToken.balanceOf(address(this));

        // Withdraw LP Token (Stargate) from Stargate LP Farming contract
        stargateLPFarming.withdraw(farmingPoolID, _amountMVLpToken);

        // Snapshot Stargate LP token balance after unstake
        uint256 afterBalance = sgLPToken.balanceOf(address(this));

        // Burn User's MV-LP token
        _burn(msg.sender, _amountMVLpToken);

        // Snapshot USDC balance before remove liquidity
        uint256 prevUSDCBalance = usdc.balanceOf(address(this));

        // Get exact amount of USDC received after removing liquidity
		uint256 sgLPTokenReceived = afterBalance.sub(prevBalance);

        // Withdraw USDC from Stargate Pool via Stargate Router
        stargateRouter.instantRedeemLocal(
            stargatePoolID, 
            sgLPTokenReceived,
            address(this)
        );

        // Snapshot USDC balance after remove liquidity
        uint256 afterUSDCBalance = usdc.balanceOf(address(this));

        // Get exact amount of USDC transferred to user
		uint256 amountUSDCTransferred = afterUSDCBalance.sub(prevUSDCBalance);

        // Transfer $USDC to user
        emit USDCwithdraw(msg.sender, _amountMVLpToken, amountUSDCTransferred);

        usdc.transfer(msg.sender, amountUSDCTransferred);
    }

    function settle() public nonReentrant onlyOwner{
        // Claim All $STG rewards from Stargate LP Farming contract
        stargateLPFarming.deposit(farmingPoolID, 0);
        
        // Get STG Balance Contract
        uint256 amountSTG = stg.balanceOf(address(this));

        // Created Path 
        address[] memory path = new address[](2);
        path[0] = address(stg);
        path[1] = address(usdc);

        uint amountOutMin = sushiSwapRouter.getAmountsOut(amountSTG, path)[1];

        // Execute the Tokens Swap from $STG to $USDC
        sushiSwapRouter.swapExactTokensForTokens(
            amountSTG, 
            amountOutMin, 
            path, 
            address(this), 
            block.timestamp
        );

        // Emit Settle Event
        emit Settle(msg.sender, amountSTG, amountOutMin);
    }
    
    function withdrawMAGIC(uint256 _amountMAGIC) public nonReentrant onlyOwner {
        // Get STG Balance Contract
        uint256 amountMAGIC = magic.balanceOf(address(this));

        if(_amountMAGIC == 0) revert ZeroWithdrawMAGIC();
        if(_amountMAGIC > amountMAGIC) revert NotEnoughMAGIC();

        magic.transfer(msg.sender, _amountMAGIC);
    }

    function setSignerAddress(address _signer) public onlyOwner {
        signer = _signer;
    }
}
