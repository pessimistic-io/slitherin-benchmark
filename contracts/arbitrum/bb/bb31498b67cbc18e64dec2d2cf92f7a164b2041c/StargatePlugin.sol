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
import "./Factory.sol";

/// @title StargatePlugin.sol
/// @notice Core trading logic for stake, unstake of Stargate pools
contract StargatePlugin is IPlugin, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /// CONSTANTS
    uint256 public constant BP_DENOMINATOR   = 10000;
    uint8 internal constant MOZAIC_DECIMALS  = 6;
    uint8 internal constant TYPE_SWAP_REMOTE = 1;

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
    mapping(uint16 => address) vaultsLookup;
    uint256 public mozaicFeeBP;
    uint256 public treasuryFeeBP;

    /* ========== EVENTS =========== */
    event StakeToken (
        address token,
        uint256 amountLD
    );

    event UnstakeToken (
        address token,
        uint256 amountLP
    );

    event GetTotalAsset(uint256 totalAssetsMD);

    event ClaimReward();
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
    /// @param _insurance - the address of the insurance.
    /// @dev Must only be called by the owner
    function setTreasury(address _treasury, address _insurance) external onlyOwner {
        require(_treasury != address(0x0) && _insurance != address(0x0), "StargatePlugin: Error Invalid addr");
        // require(localTreasury == address(0x0) && localInsurance == address(0x0), "StargatePlugin: The treasury has already been set.");
        localTreasury = _treasury;
        localInsurance = _insurance;
    }

    /// @notice Set the treasury and insurance.
    /// @param _mozaicFeeBP - The mozaic fee percent of total fee. 100 = 1%
    /// @param _treasuryFeeBP - The treasury fee percent of mozaic fee. 100 = 1%
    function setFee(uint256 _mozaicFeeBP, uint256 _treasuryFeeBP) external onlyOwner {
        require(_mozaicFeeBP <= BP_DENOMINATOR && _treasuryFeeBP <= BP_DENOMINATOR, "StargatePlugin: fees > 100%");
        mozaicFeeBP = _mozaicFeeBP;
        treasuryFeeBP = _treasuryFeeBP;
    }

    /// @notice Config plugin with the params.
    /// @param _stgRouter - The address of router.
    /// @param _stgLPStaking - The address of LPStaking.
    /// @param _stgToken - The address of stargate token.
    function configPlugin(address _stgRouter, address _stgLPStaking, address _stgToken) public onlyOwner {
        require(_stgRouter != address(0) && _stgLPStaking != address(0) && _stgToken != address(0), "StargatePlugin: Invalid address");
        // require(config.stgRouter == address(0) && config.stgLPStaking == address(0) && config.stargateToken == address(0), "StargatePlugin: The plugin is already configured.");
        config.stgRouter = _stgRouter;
        config.stgLPStaking = _stgLPStaking;
        config.stargateToken = _stgToken;
    }

    function setVaultsLookup(uint16 _chainId, address _vaultAddress) public onlyOwner {
        require(_chainId > 0 && _vaultAddress != address(0), "StargatePlugin: invalid param");
        // require(vaultsLookup[_chainId] == address(0), "StargatePlugin: vaultlookup already set");
        vaultsLookup[_chainId] = _vaultAddress;
    }

    /* ========== PUBLIC FUNCTIONS ========== */
    
    /// @notice Main StargatePlugin function. Execute the action to StargatePlugin depending on Action passed in.
    /// @param _actionType - The type of the action to be executed.
    /// @param _payload - a custom bytes payload to execute the action.
    function execute(ActionType _actionType, bytes calldata _payload) public payable onlyVault returns (bytes memory response) {
        if (_actionType != ActionType.SwapRemote) {
            require(msg.value == 0, "StargatePlugin: Invalid value");
        }
        if (_actionType == ActionType.Stake) {
            response = _stake(_payload);
        } else if (_actionType == ActionType.Unstake) {
            response = _unstake(_payload);
        } else if (_actionType == ActionType.GetTotalAssetsMD) {
            response = _getTotalAssetsMD(_payload);
        } else if (_actionType == ActionType.ClaimReward) {
            response = _claimReward(_payload);
        } else if (_actionType == ActionType.SwapRemote) {
            response = _swapRemote(_payload);
        } else {
            revert("StargatePlugin: Undefined Action");
        }
    }

    /* ========== VIEW FUNCTIONS ========== */

    /// @notice Get the staked amount of the token
    function getStakedAmount(address _token) public view returns(uint256, uint256) {
        address pool = _getStargatePoolFromToken(_token);
        if(pool == address(0)) return (0, 0);
        address _stgLPStaking = config.stgLPStaking;
        (bool found, uint256 stkPoolIndex) = _getPoolIndexInFarming(pool);
        if(found == false) return (0, 0);
        uint256 _amountLPStaked = IStargateLpStaking(_stgLPStaking).userInfo(stkPoolIndex, address(this)).amount;
        uint256 _amountLDStaked = (_amountLPStaked  == 0) ? 0 : IStargatePool(pool).amountLPtoLD(_amountLPStaked);
        return (_amountLDStaked, _amountLPStaked);
    }

    /// @notice Get the staked amount of the token
    function amountLPtoLD(address _token, uint256 _amountLP) public view returns(uint256) {
        require(isAcceptingToken(_token), "Not Supported token");
        address pool = _getStargatePoolFromToken(_token);
        uint256 _amountLD = (_amountLP  == 0) ? 0 : IStargatePool(pool).amountLPtoLD(_amountLP);
        return _amountLD;
    }

    function isAcceptingToken(address _token) public view returns (bool) {
        address pool = _getStargatePoolFromToken(_token);
        if(pool == address(0)) return false;
        (bool found,) = _getPoolIndexInFarming(pool);
        return found;
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

        
        // Transfer approved token from vault to plugin
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amountLD);

        address _stgRouter = config.stgRouter;
        IERC20(_token).safeApprove(_stgRouter, 0);
        IERC20(_token).approve(_stgRouter, _amountLD);

        // Stake token from vault to STG.Pool and get LPToken
        // 1. Pool.LPToken of vault before
        uint256 balanceBefore = IStargatePool(_pool).balanceOf(address(this));

        // 2. Plugin adds liquidity
        IStargateRouter(_stgRouter).addLiquidity(_poolId, _amountLD, address(this));

        // 3. Pool.LPToken of plugin after
        uint256 balanceAfter = IStargatePool(_pool).balanceOf(address(this));
        // 4. Increased LPToken of vault
        uint256 amountLPToken = balanceAfter - balanceBefore;

        // Find the Liquidity Pool's index in the Farming Pool.
        (bool found, uint256 stkPoolIndex) = _getPoolIndexInFarming(_pool);
        require(found, "StargatePlugin: The LP token not acceptable.");
        
        // Deposit LPToken from plugin to LPStaking
        address _stgLPStaking = config.stgLPStaking;
        IStargatePool(_pool).approve(_stgLPStaking, 0);
        IStargatePool(_pool).approve(_stgLPStaking, amountLPToken);

        // Stake LPToken from plugin to LPStaking
        IStargateLpStaking(_stgLPStaking).deposit(stkPoolIndex, amountLPToken);

        // Withdraw token to the localVault
       _withdrawToken(_token);
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
        (bool found, uint256 stkPoolIndex) = _getPoolIndexInFarming(_pool);
        require(found, "StargatePlugin: The LP token not acceptable.");

        // Withdraw LPToken from LPStaking to plugin
        // 1. Pool.LPToken of plugin before
        uint256 balanceBefore = IStargatePool(_pool).balanceOf(address(this));

        // 2. Withdraw LPToken from LPStaking to plugin
        address _stgLPStaking = config.stgLPStaking;
        
        uint256 _stakedLP = IStargateLpStaking(_stgLPStaking).userInfo(stkPoolIndex, address(this)).amount;

        if(_stakedLP < _amountLPToken) _amountLPToken = _stakedLP;
        
        IStargateLpStaking(_stgLPStaking).withdraw(stkPoolIndex, _amountLPToken);

        // 3. Increased LPToken of plugin
        uint256 _amountLPTokenWithdrawn = IStargatePool(_pool).balanceOf(address(this)) - balanceBefore;

        // Give LPToken and redeem token from STG.Pool to plugin
        address _stgRouter = config.stgRouter;
        IStargateRouter(_stgRouter).instantRedeemLocal(uint16(_poolId), _amountLPTokenWithdrawn, address(this));

        // Stake remained LP token 
        uint256 _balance = IStargatePool(_pool).balanceOf(address(this));
        IStargatePool(_pool).approve(_stgLPStaking, 0);
        IStargatePool(_pool).approve(_stgLPStaking, _balance);
        IStargateLpStaking(_stgLPStaking).deposit(stkPoolIndex, _balance);

        // Withdraw token to the localVault
       _withdrawToken(_token);

        // Transfer stargateToken to localVault
        _distributeReward();
        
        emit UnstakeToken(_token, _amountLPTokenWithdrawn);
    }
    
    /// @notice Gets total assets per token.
    /// @dev the action function called by execute.
    function _getTotalAssetsMD(bytes calldata _payload) private returns (bytes memory) {
        (address[] memory _tokens) = abi.decode(_payload, (address[]));

        // The total stablecoin amount with mozaic deciaml
        uint256 _totalAssetsMD;
        uint256 _assetsMD;
        for (uint i; i < _tokens.length; ++i) {
            address _token = _tokens[i];

            // Get assets LD in plugin
            uint256 _assetsLD = IERC20(_token).balanceOf(address(this));
            
            if(_assetsLD > 0) {
                //Transfer token to localVault
                IERC20(_token).safeTransfer(localVault, _assetsLD); 
            }

            // Get assets LD staked in LPStaking
            // Get pool address
            address _pool = _getStargatePoolFromToken(_token);
            if(_pool == address(0)) {
                _assetsMD = convertLDtoMD(_token, _assetsLD);
                _totalAssetsMD = _totalAssetsMD + _assetsMD;
                continue;
            }
            
            // Find the Liquidity Pool's index in the Farming Pool.
            (bool found, uint256 stkPoolIndex) = _getPoolIndexInFarming(_pool);
            if(found == false) {
                _assetsMD = convertLDtoMD(_token, _assetsLD);
                _totalAssetsMD = _totalAssetsMD + _assetsMD;
                continue;
            }

            // Collect pending STG rewards: _stgLPStaking = config.stgLPStaking.withdraw(poolIndex, 0)
            address _stgLPStaking = config.stgLPStaking;
            IStargateLpStaking(_stgLPStaking).withdraw(stkPoolIndex, 0);

            // Get amount LP staked
            uint256 _amountLPStaked = IStargateLpStaking(_stgLPStaking).userInfo(stkPoolIndex, address(this)).amount;
            
            // Get amount LD for token.
            _assetsLD = _assetsLD + ((_amountLPStaked  == 0) ? 0 : IStargatePool(_pool).amountLPtoLD(_amountLPStaked));
            _assetsMD = convertLDtoMD(_token, _assetsLD);
            _totalAssetsMD = _totalAssetsMD + _assetsMD;
        }
        bytes memory result = abi.encode(_totalAssetsMD);
        // Transfer stargateToken to localVault
        _distributeReward();
        emit GetTotalAsset(_totalAssetsMD);
        return result;
    }

    /// @notice Claim reward for a specific token
    /// @dev the action function called by execute.
    function _claimReward(bytes calldata _payload) private returns (bytes memory) {
        (address[] memory _tokens) = abi.decode(_payload, (address[]));
        for(uint256 i = 0; i < _tokens.length; ++i) {
            address pool = _getStargatePoolFromToken(_tokens[i]);
            if(pool == address(0)) continue;
            address _stgLPStaking = config.stgLPStaking;
            (bool found, uint256 stkPoolIndex) = _getPoolIndexInFarming(pool);
            if(found == false) continue;
            IStargateLpStaking(_stgLPStaking).withdraw(stkPoolIndex, 0);
        }
        _distributeReward();
        emit ClaimReward();
    }

    /// @notice SwapRemote the token.
    /// @dev the action function called by execute.
    function _swapRemote(bytes calldata _payload) private returns (bytes memory) {
        uint256 _amountLD;
        uint16 _dstChainId;
        uint256 _dstPoolId;
        uint256 _srcPoolId;
        address _router;
        // To avoid stack deep error
        {
            address _srcToken;
            (_amountLD, _srcToken, _dstChainId, _dstPoolId) = abi.decode(_payload, (uint256, address, uint16, uint256));
            require (_amountLD > 0, "Cannot swapRemote zero amount");
            IERC20(_srcToken).safeTransferFrom(localVault, address(this), _amountLD);
            address _srcPool = _getStargatePoolFromToken(_srcToken);
            require(_srcPool != address(0), "StargatePlugin: Invalid source token.");
            _srcPoolId = IStargatePool(_srcPool).poolId();
            
            _router = config.stgRouter;
            IERC20(_srcToken).approve(_router, _amountLD);
        }
        address _to = vaultsLookup[_dstChainId];
        require(_to != address(0x0), "StargatePlugin: _to cannot be 0x0");
        // Quote native fee
        (uint256 _nativeFee, ) = IStargateRouter(_router).quoteLayerZeroFee(_dstChainId, TYPE_SWAP_REMOTE, abi.encodePacked(_to), bytes(""), IStargateRouter.lzTxObj(0, 0, "0x"));
        require(msg.value >= _nativeFee, "StargatePlugin: Not enough native fee");
        // SwapRemote
        IStargateRouter(_router).swap{value: msg.value}(_dstChainId, _srcPoolId, _dstPoolId, payable(localVault), _amountLD, 0, IStargateRouter.lzTxObj(0, 0, "0x"), abi.encodePacked(_to), bytes(""));
    }

    function quoteSwapFee(uint16 _dstChainId) public view returns (uint256) {
        address _to = vaultsLookup[_dstChainId];
        require(_to != address(0x0), "StargatePlugin: _to cannot be 0x0");
        address _router = config.stgRouter;
        (uint256 _nativeFee, ) = IStargateRouter(_router).quoteLayerZeroFee(_dstChainId, TYPE_SWAP_REMOTE, abi.encodePacked(_to), bytes(""), IStargateRouter.lzTxObj(0, 0, "0x"));
        return _nativeFee;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /// @notice Gets pool from the token address.
    function _getStargatePoolFromToken(address _token) internal view returns (address) {
        address _router = config.stgRouter;
        Factory _factory = IStargateRouter(_router).factory();
        uint256 _allPoolsLength = IStargateFactory(address(_factory)).allPoolsLength();

        for (uint i; i < _allPoolsLength; ++i) {
            address _pool = IStargateFactory(address(_factory)).allPools(i);
            address _poolToken = IStargatePool(_pool).token();
            if (_poolToken == _token) {
                return _pool;
            }
        }
        return address(0);
    }

    /// @notice Gets pool index in farming.
    function _getPoolIndexInFarming(address _pool) internal view returns (bool, uint256) {
        address _lpStaking = config.stgLPStaking;
        uint256 _poolLength = IStargateLpStaking(_lpStaking).poolLength();
        for (uint256 i; i < _poolLength; ++i) {
            address _pool__ = IStargateLpStaking(_lpStaking).poolInfo(i).lpToken;
            if (_pool__ == _pool) {
                return (true, i);
            } 
        }
        return (false, 0);
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

    /// @notice withdraw token to the local vault
    function _withdrawToken(address _token) internal {
        uint256 _tokenAmount = IERC20(_token).balanceOf(address(this));
        if(_tokenAmount > 0) {
            IERC20(_token).safeTransfer(localVault, _tokenAmount);
        }
    }

    /// @notice  distribute the stargateToken to vault, treasury and insurance.
    function _distributeReward() internal {
        address _stargateToken = config.stargateToken;
        uint256 _stgAmount = IERC20(_stargateToken).balanceOf(address(this));
        if(_stgAmount == 0) return;
        if(localInsurance == address(0) || localTreasury == address(0)) return;  
        uint256 _mozaicAmount = _stgAmount.mul(mozaicFeeBP).div(BP_DENOMINATOR);
        _stgAmount = _stgAmount.sub(_mozaicAmount);
        uint256 _treasuryAmount = _mozaicAmount.mul(treasuryFeeBP).div(BP_DENOMINATOR);
        uint256 _insuranceAmount = _mozaicAmount.sub(_treasuryAmount);
        if(_stgAmount != 0) IERC20(_stargateToken).safeTransfer(localVault, _stgAmount);
        if(_treasuryAmount != 0) IERC20(_stargateToken).safeTransfer(localTreasury, _treasuryAmount);
        if(_insuranceAmount != 0) IERC20(_stargateToken).safeTransfer(localInsurance, _insuranceAmount);
    }
}
