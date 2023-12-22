// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.9;

// imports
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./Ownable.sol";

// libraries
import "./SafeMath.sol";
import "./SafeERC20.sol";

import "./IStargateRouter.sol";
import "./IStargatePool.sol";
import "./IStargateLpStaking.sol";
import "./IStargateFactory.sol";
import "./IPlugin.sol";

/// @title StargatePlugin.sol
/// @notice Core trading logic for stake, unstake of Stargate pools
contract StargatePlugin is IPlugin, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// CONSTANTS
    uint256 public constant BP_DENOMINATOR   = 10000;
    bytes32 public constant CONFIG_SLOT = keccak256("StargateDriver.config");
    uint8 internal constant MOZAIC_DECIMALS  = 6;

    ///@dev Used to define StargatePlugin config
    struct StargatePluginConfig {
        address stgRouter;
        address stgLPStaking;
        address stargateToken;
    }

    /* ========== STATE VARIABLES ========== */
    address public localVault;
    address public localTreasury;
    address public localInsurance;
    StargatePluginConfig public config;
    uint256 public mozaicFeeBP;
    uint256 public treasuryFeeBP;
    mapping(address => uint256) public stackedAmountPerToken;

    /* ========== EVENTS =========== */
    event StakeToken (
        address token,
        uint256 amountLD
    );

    event UnstakeToken (
        address token,
        uint256 amountLP
    );
    
    event GetStakedAmountLDPerToken (
        address token,
        uint256 amountLP
    );
    event GetTotalAsset(uint256 totalAssetsMD);
    /* ========== MODIFIERS ========== */

    /// @notice Modifier to check if caller is the vault.
    modifier onlyVault() {
        require(msg.sender == localVault, "StargatePlugin: caller is not the vault");
        _;
    }

    /* ========== CONFIGURATION ========== */
    constructor(
        address _localVault
    ) {
        require(_localVault != address(0x0), "ERROR: Invalid addr");
        localVault = _localVault;
    }

    /// @notice Set the vault address.
    /// @param _localVault - the address of the vault.
    function setVault(address _localVault) external onlyOwner {
        require(_localVault != address(0x0), "ERROR: Invalid addr");
        localVault = _localVault;
    }

    /// @notice Set the treasury and insurance.
    /// @param _treasury - the address of the treasury.
    /// @param _insurance - the address of the treasury.
    /// @dev Must only be called by the owner
    function setTreasury(address _treasury, address _insurance) external onlyOwner {
        require(_treasury != address(0x0), "StargatePlugin: Error Invalid addr");
        require(_insurance != address(0x0), "StargatePlugin: Error Invalid addr");
        localTreasury = _treasury;
        localInsurance = _insurance;
    }

    /// @notice Set the treasury and insurance.
    /// @param _mozaicFeeBP - The mozaic fee percent of total fee. 100 = 1%
    /// @param _treasuryFeeBP - The treasury fee percent of mozaic fee. 100 = 1%
    function setFee(uint256 _mozaicFeeBP, uint256 _treasuryFeeBP) external onlyOwner {
        require(_mozaicFeeBP <= BP_DENOMINATOR, "StargatePlugin: fees > 100%");
        require(_treasuryFeeBP <= BP_DENOMINATOR, "StargatePlugin: fees > 100%");

        mozaicFeeBP = _mozaicFeeBP;
        treasuryFeeBP = _treasuryFeeBP;
    }

    /// @notice Config plugin with the params.
    /// @param _stgRouter - The address of router.
    /// @param _stgLPStaking - The address of LPStaking.
    /// @param _stgToken - The address of stargate token.
    function configPlugin(address _stgRouter, address _stgLPStaking, address _stgToken) public onlyOwner {
        config.stgRouter = _stgRouter;
        config.stgLPStaking = _stgLPStaking;
        config.stargateToken = _stgToken;
    }

    /* ========== PUBLIC FUNCTIONS ========== */
    
    /// @notice Main StargatePlugin function. Execute the action to StargatePlugin depending on Action passed in.
    /// @param _actionType - The type of the action to be executed.
    /// @param _payload - a custom bytes payload to execute the action.
    function execute(ActionType _actionType, bytes calldata _payload) public onlyVault returns (bytes memory response) {
        if (_actionType == ActionType.Stake) {
            response = _stake(_payload);
        }
        else if (_actionType == ActionType.Unstake) {
            response = _unstake(_payload);
        }
        else if (_actionType == ActionType.GetStakedAmountLD) {
            response = _getStakedAmountLDPerToken(_payload);
        }
        else if (_actionType == ActionType.GetTotalAssetsMD) {
            response = _getTotalAssetsMD(_payload);
        }
        else {
            revert("StargatePlugin: Undefined Action");
        }
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    /// @notice Main staking function.
    /// @dev the action function called by execute.
    function _stake(bytes calldata _payload) private returns (bytes memory) {
        (uint256 _amountLD, address _token) = abi.decode(_payload, (uint256, address));
        require (_amountLD > 0, "StargatePlugin: Cannot stake zero amount");
        
        // Get pool and poolId
        address _pool = _getStargatePoolFromToken(_token);
        require(_pool != address(0), "StargatePlugin: Invalid token");
        uint256 _poolId = IStargatePool(_pool).poolId();

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amountLD);
        // Approve token transfer from vault to STG.Pool
        address _stgRouter = config.stgRouter;
        IERC20(_token).safeApprove(_stgRouter, 0);
        IERC20(_token).approve(_stgRouter, _amountLD);

        // Stake token from vault to STG.Pool and get LPToken
        // 1. Pool.LPToken of vault before
        uint256 balanceBefore = IStargatePool(_pool).balanceOf(address(this));

        // 2. Vault adds liquidity
        IStargateRouter(_stgRouter).addLiquidity(_poolId, _amountLD, address(this));

        // 3. Pool.LPToken of vault after
        uint256 balanceAfter = IStargatePool(_pool).balanceOf(address(this));
        // 4. Increased LPToken of vault
        uint256 amountLPToken = balanceAfter - balanceBefore;

        // Find the Liquidity Pool's index in the Farming Pool.
        (bool found, uint256 stkPoolIndex) = _getPoolIndexInFarming(_poolId);
        require(found, "StargatePlugin: The LP token not acceptable.");
        
        // Approve LPToken transfer from vault to LPStaking
        address _stgLPStaking = config.stgLPStaking;
        IStargatePool(_pool).approve(_stgLPStaking, 0);
        IStargatePool(_pool).approve(_stgLPStaking, amountLPToken);

        // Stake LPToken from vault to LPStaking
        IStargateLpStaking(_stgLPStaking).deposit(stkPoolIndex, amountLPToken);

        // Update the staked amount per token
        uint256 _amountLPStaked = IStargateLpStaking(_stgLPStaking).userInfo(stkPoolIndex, address(this)).amount;
        stackedAmountPerToken[_token] = (_amountLPStaked  == 0) ? 0 : IStargatePool(_pool).amountLPtoLD(_amountLPStaked);

        //Transfer token to localVault
        uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
        if(_tokenAmount > 0) {
            IERC20(_token).safeTransfer(localVault, _tokenAmount);
        }

        // Transfer stargateToken to localVault
        _distributeReward();
        emit StakeToken(_token, _amountLD);
    }

    /// @notice Main unstaking function.
    /// @dev the action function called by execute.
    function _unstake(bytes calldata _payload) private returns (bytes memory) {
        (uint256 _amountLPToken, address _token) = abi.decode(_payload, (uint256, address));
        require (_amountLPToken > 0, "StargatePlugin: Cannot unstake zero amount");

        // Get pool and poolId
        address _pool = _getStargatePoolFromToken(_token);
        require(_pool != address(0), "StargatePlugin: Invalid token");

        uint256 _poolId = IStargatePool(_pool).poolId();
        
        // Find the Liquidity Pool's index in the Farming Pool.
        (bool found, uint256 stkPoolIndex) = _getPoolIndexInFarming(_poolId);
        require(found, "StargatePlugin: The LP token not acceptable.");

        // Withdraw LPToken from LPStaking to vault
        // 1. Pool.LPToken of vault before
        uint256 balanceBefore = IStargatePool(_pool).balanceOf(address(this));

        // 2. Withdraw LPToken from LPStaking to vault
        address _stgLPStaking = config.stgLPStaking;
        
        uint256 _stakedLP = IStargateLpStaking(_stgLPStaking).userInfo(stkPoolIndex, address(this)).amount;

        if(_stakedLP < _amountLPToken) _amountLPToken = _stakedLP;
        
        IStargateLpStaking(_stgLPStaking).withdraw(stkPoolIndex, _amountLPToken);

        // 3. Pool.LPToken of vault after
        // uint256 balanceAfter = ;
        // 4. Increased LPToken of vault
        uint256 _amountLPTokenWithdrawn = IStargatePool(_pool).balanceOf(address(this)) - balanceBefore;

        // Give LPToken and redeem token from STG.Pool to vault
        address _stgRouter = config.stgRouter;
        IStargateRouter(_stgRouter).instantRedeemLocal(uint16(_poolId), _amountLPTokenWithdrawn, address(this));

        // Stake remained LP token 
        uint256 _balance = IStargatePool(_pool).balanceOf(address(this));
        IStargatePool(_pool).approve(_stgLPStaking, 0);
        IStargatePool(_pool).approve(_stgLPStaking, _balance);
        IStargateLpStaking(_stgLPStaking).deposit(stkPoolIndex, _balance);

        // Update the staked amount per token
        uint256 _amountLPStaked = IStargateLpStaking(_stgLPStaking).userInfo(stkPoolIndex, address(this)).amount;
        stackedAmountPerToken[_token] = (_amountLPStaked  == 0) ? 0 : IStargatePool(_pool).amountLPtoLD(_amountLPStaked);

        //Transfer token to localVault
        uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
        if(_tokenAmount > 0) {
            IERC20(_token).safeTransfer(localVault, _tokenAmount);
        }

        // Transfer stargateToken to localVault
        _distributeReward();
        
        emit UnstakeToken(_token, _amountLPTokenWithdrawn);
    }
    
    /// @notice Gets staked amount per token.
    /// @dev the action function called by execute.
    function _getStakedAmountLDPerToken(bytes calldata _payload) private returns (bytes memory) {
        (address _token) = abi.decode(_payload, (address));

        // Get pool address
        address _pool = _getStargatePoolFromToken(_token);
        bytes memory result;
        if(_pool == address(0)) {
            result = abi.encode(0);
            return result;
        }
        // Get pool id: _poolId = _pool.poolId()
        uint256 _poolId = IStargatePool(_pool).poolId();

        // Find the Liquidity Pool's index in the Farming Pool.
        (bool found, uint256 poolIndex) = _getPoolIndexInFarming(_poolId);
        if(found == false) {
            result = abi.encode(0);
            return result;
        }

        // Collect pending STG rewards: _stgLPStaking = config.stgLPStaking.withdraw(poolIndex, 0)
        address _stgLPStaking = config.stgLPStaking;
        IStargateLpStaking(_stgLPStaking).withdraw(poolIndex, 0);

        // Get amount LP staked
        uint256 _amountLP = IStargateLpStaking(_stgLPStaking).userInfo(poolIndex, address(this)).amount;

        // Get amount LD staked
        uint256 _amountLD = (_amountLP  == 0) ? 0 : IStargatePool(_pool).amountLPtoLD(_amountLP);
        result = abi.encode(_amountLD);

        //Transfer token to localVault
        uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
        if(_tokenAmount > 0) {
            IERC20(_token).safeTransfer(localVault, _tokenAmount);
        }
        // Transfer stargateToken to localVault
        _distributeReward();
        emit GetStakedAmountLDPerToken(_token, _amountLD);
        return result;
    }

    /// @notice Gets total assets per token.
    /// @dev the action function called by execute.
    function _getTotalAssetsMD(bytes calldata _payload) private returns (bytes memory) {
        (address[] memory _tokens) = abi.decode(_payload, (address[]));

        // The total stablecoin amount with mozaic deciaml
        uint256 _totalAssetsMD;
        for (uint i; i < _tokens.length; ++i) {
            address _token = _tokens[i];

            // Get assets LD in vault
            uint256 _assetsLD = IERC20(_token).balanceOf(address(this));
            
            if(_assetsLD > 0) {
                //Transfer token to localVault
                IERC20(_token).safeTransfer(localVault, _assetsLD); 
            }

            
            // Get assets LD staked in LPStaking
            // Get pool address
            address _pool = _getStargatePoolFromToken(_token);
            if(_pool == address(0)) continue;

            // Get pool id: _poolId = _pool.poolId()
            uint256 _poolId = IStargatePool(_pool).poolId();
            
            // Find the Liquidity Pool's index in the Farming Pool.
            (bool found, uint256 poolIndex) = _getPoolIndexInFarming(_poolId);
            if(found == false) continue;

            // Collect pending STG rewards: _stgLPStaking = config.stgLPStaking.withdraw(poolIndex, 0)
            address _stgLPStaking = config.stgLPStaking;
            IStargateLpStaking(_stgLPStaking).withdraw(poolIndex, 0);

            // Get amount LP staked
            uint256 _amountLPStaked = IStargateLpStaking(_stgLPStaking).userInfo(poolIndex, address(this)).amount;
            stackedAmountPerToken[_token] = (_amountLPStaked  == 0) ? 0 : IStargatePool(_pool).amountLPtoLD(_amountLPStaked);
            
            // Get amount LD for token.
            _assetsLD = _assetsLD + stackedAmountPerToken[_token];
            uint256 _assetsMD = convertLDtoMD(_token, _assetsLD);
            _totalAssetsMD = _totalAssetsMD + _assetsMD;
        }
        bytes memory result = abi.encode(_totalAssetsMD);
        // Transfer stargateToken to localVault
        _distributeReward();
        emit GetTotalAsset(_totalAssetsMD);
        return result;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @notice Gets pool from the token address.
    function _getStargatePoolFromToken(address _token) internal returns (address) {
        address _router = config.stgRouter;
        
        (bool success, bytes memory response) = address(_router).call(abi.encodeWithSignature("factory()"));
        require(success, "StargatePlugin: factory failed");
        address _factory = abi.decode(response, (address));
        uint256 _allPoolsLength = IStargateFactory(_factory).allPoolsLength();

        for (uint i; i < _allPoolsLength; ++i) {
            address _pool = IStargateFactory(_factory).allPools(i);
            address _poolToken = IStargatePool(_pool).token();
            if (_poolToken == _token) {
                return _pool;
            } else {
                continue;
            }
        }
        return address(0);
    }

    /// @notice Gets pool index in farming.
    function _getPoolIndexInFarming(uint256 _poolId) internal returns (bool, uint256) {
        address _pool = _getPool(_poolId);
        address _lpStaking = config.stgLPStaking;
        uint256 _poolLength = IStargateLpStaking(_lpStaking).poolLength();

        for (uint256 poolIndex; poolIndex < _poolLength; poolIndex++) {
            address _pool__ = IStargateLpStaking(_lpStaking).getPoolInfo(poolIndex);
            if (_pool__ == _pool) {
                return (true, poolIndex);
            } else {
                continue;
            }
        }
        return (false, 0);
    }

    /// @notice Gets pool from the pool id.
    function _getPool(uint256 _poolId) internal returns (address _pool) {
        address _router = config.stgRouter;

         (bool success, bytes memory response) = _router.call(abi.encodeWithSignature("factory()"));
        require(success, "StargatePlugin: factory failed");
        address _factory = abi.decode(response, (address));
        
        _pool = IStargateFactory(_factory).getPool(_poolId);
        require(address(_pool) != address(0x0), "StargatePlugin:  Invalid pool Id");
    }

    /// @notice  convert local decimal to mozaic decimal.
    function convertLDtoMD(address _token, uint256 _amountLD) internal view returns (uint256) {
        uint256 _localDecimals = IERC20Metadata(_token).decimals();
        if (MOZAIC_DECIMALS >= _localDecimals) {
            return _amountLD * (10**(MOZAIC_DECIMALS - _localDecimals));
        } else {
            return _amountLD / (10**(_localDecimals - MOZAIC_DECIMALS));
        }
    }

    /// @notice  distribute the stargateToken to vault, treasury and insurance.
    function _distributeReward() internal {
        address _stargateToken = config.stargateToken;
        uint256 _stgAmount = IERC20(_stargateToken).balanceOf(address(this));
        if(_stgAmount == 0) return;
        uint256 _mozaicAmount = _stgAmount.mul(mozaicFeeBP).div(BP_DENOMINATOR);
        _stgAmount = _stgAmount.sub(_mozaicAmount);
        uint256 _treasuryAmount = _mozaicAmount.mul(treasuryFeeBP).div(BP_DENOMINATOR);
        uint256 _insuranceAmount = _mozaicAmount.sub(_treasuryAmount);

        IERC20(_stargateToken).safeTransfer(localVault, _stgAmount);
        IERC20(_stargateToken).safeTransfer(localTreasury, _treasuryAmount);
        IERC20(_stargateToken).safeTransfer(localInsurance, _insuranceAmount);
    }
}
