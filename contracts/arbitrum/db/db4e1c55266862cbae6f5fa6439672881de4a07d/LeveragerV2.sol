// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "./SafeMath.sol";
import "./IERC20.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./IPool.sol";
import "./FlashLoanReceiverBase.sol";
import "./IPoolAddressesProvider.sol";

interface IGmxRewardRoter {
    function mintAndStakeGlp(
        address _token,
        uint256 _amount,
        uint256 _minUsdg,
        uint256 _minGlp
    ) external returns (uint256);
}

interface IProtocolDataProvider {
    function getReserveConfigurationData(
        address asset
    )
        external
        view
        returns (
            uint256 decimals,
            uint256 ltv,
            uint256 liquidationThreshold,
            uint256 liquidationBonus,
            uint256 reserveFactor,
            bool usageAsCollateralEnabled,
            bool borrowingEnabled,
            bool stableBorrowRateEnabled,
            bool isActive,
            bool isFrozen
        );
}

interface IProtocolOracle {
    function getAssetPrice(address asset) external view returns (uint256);
}

/**
 * @title   Leverager
 * @author  Maneki.finance
 * @notice  Allow users to leverage lending position on one click on one click
 */

contract LeveragerV2 is
    FlashLoanReceiverBase,
    Ownable,
    ReentrancyGuard,
    Pausable
{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== CONTSTANTS ========== */
    uint256 constant RATIO_DIVISOR = 10000;

    /* ========== VARIABLES ========== */

    /* Gmx Reward Router */
    IGmxRewardRoter public gmxRewardRouter;

    /* Gmx Reward Router */
    IProtocolDataProvider public protocolDataProvider;

    /* LendingPool*/
    IPool public pool;

    /* Protocol Oracle */
    IProtocolOracle public protocolOracle;

    /* Address of Glp Token */
    address public glpToken;

    /* Address of Weth Token */
    address public weth;

    /* Other accepted collaterals */
    mapping(address => bool) public acceptedCollateral;

    /* Other accepted borrowable */
    mapping(address => bool) public acceptedBorrowAssets;

    /* ========== EVENTS ========== */

    event LeveragedGlpPosition(
        address user,
        uint256 leverage,
        uint256 glpPosition
    );

    event SetValidCollateral(address collateral, bool validity);

    event SetValidBorrowAssets(address borrowAsset, bool validity);

    constructor(
        address _poolAddressesProvider,
        address _glpToken,
        address _weth,
        address _gmxRewardRouter,
        address _protocolDataProvider,
        address _pool,
        address _protocolOracle
    ) FlashLoanReceiverBase(IPoolAddressesProvider(_poolAddressesProvider)) {
        glpToken = _glpToken;
        weth = _weth;
        gmxRewardRouter = IGmxRewardRoter(_gmxRewardRouter);
        protocolDataProvider = IProtocolDataProvider(_protocolDataProvider);
        pool = IPool(_pool);
        protocolOracle = IProtocolOracle(_protocolOracle);
        IERC20(glpToken).approve(address(pool), type(uint256).max);
    }

    function leverageGlp(
        address _collateral,
        uint256 _amount,
        address[] calldata _borrowTokens,
        uint256[] calldata _ratio,
        uint256 _leverage //
    ) external nonReentrant {
        /* Parse arguments */
        require(
            _collateral == glpToken || acceptedCollateral[_collateral],
            "Invalid collateral"
        );
        require(
            _borrowTokens.length == _ratio.length,
            "_borrowTokens and _ratio length must be equial"
        );
        require(
            _checkValidBorrowTokens(_borrowTokens),
            "Invalid borrow tokens"
        );
        require(_checkValidRatio(_ratio), "Invalid ratio");

        /* Check ltv */
        (, uint256 maxGlpLtv, , , , , , , , ) = protocolDataProvider
            .getReserveConfigurationData(glpToken);

        /* Check whether intended leverage is higher than max possible leverage */
        /* Intentianally omit decimals */
        require(
            _leverage < (RATIO_DIVISOR) / (RATIO_DIVISOR - maxGlpLtv),
            "Invalid leverage value"
        );

        /* Transfer colletaral to contract */
        IERC20(_collateral).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        ); // Collateral allowances: msg.sender => Leverager

        /* If collateral not glpToken, mint and stake on behalf of user */
        uint256 glpAmount = _collateral == glpToken
            ? _amount
            : gmxRewardRouter.mintAndStakeGlp(_collateral, _amount, 0, 0); // Collateral allowances: Leverager => RewardRouter

        /* Calculate collateral value */
        uint256 collateralUsdValue = protocolOracle
            .getAssetPrice(address(glpToken))
            .mul(glpAmount)
            .div(10 ** ERC20(glpToken).decimals()); // 8 decimals USD

        /* Calculate leveraged position value */
        uint256 leveragedUsdValue = collateralUsdValue.mul(_leverage - 1); //8 decimals USD

        /* Calculate target flahloan amount */
        uint256[] memory borrowAmounts = new uint256[](_borrowTokens.length);
        uint256[] memory interestRateMode = new uint256[](_borrowTokens.length);

        for (uint256 i = 0; i < _borrowTokens.length; i++) {
            /* Calculate borrow amount for each token according to its ratio */
            uint256 flashloanUsdValue = leveragedUsdValue.mul(_ratio[i]).div(
                RATIO_DIVISOR
            ); // 8 decimals USD

            borrowAmounts[i] = flashloanUsdValue
                .mul(10 ** ERC20(_borrowTokens[i]).decimals())
                .div(protocolOracle.getAssetPrice(_borrowTokens[i]));
            interestRateMode[i] = 2;
        }
        pool.flashLoan(
            address(this),
            _borrowTokens,
            borrowAmounts,
            interestRateMode,
            msg.sender,
            abi.encode(msg.sender, _leverage),
            0
        );
    }

    function setValidCollateral(
        address[] calldata _collaterals,
        bool[] calldata _boolArray
    ) external onlyOwner {
        require(
            _collaterals.length == _boolArray.length,
            "Invalid set valid collateral length"
        );
        for (uint256 i = 0; i < _collaterals.length; i++) {
            IERC20(_collaterals[i]).approve(
                address(gmxRewardRouter),
                type(uint256).max
            );
            acceptedCollateral[_collaterals[i]] = _boolArray[i];
            emit SetValidCollateral(_collaterals[i], _boolArray[i]);
        }
    }

    function setValidBorrowAssets(
        address[] calldata _borrowAssets,
        bool[] calldata _boolArray
    ) external onlyOwner {
        require(
            _borrowAssets.length == _boolArray.length,
            "Invalid set valid borrow assets length"
        );
        for (uint256 i = 0; i < _borrowAssets.length; i++) {
            IERC20(_borrowAssets[i]).approve(
                address(gmxRewardRouter),
                type(uint256).max
            );
            acceptedBorrowAssets[_borrowAssets[i]] = _boolArray[i];
            emit SetValidBorrowAssets(_borrowAssets[i], _boolArray[i]);
        }
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice Check whether tokens intended to borrow is allowed
     */

    function _checkValidBorrowTokens(
        address[] calldata _borrowTokens
    ) internal view returns (bool) {
        for (uint256 i = 0; i < _borrowTokens.length; i++) {
            if (!acceptedBorrowAssets[_borrowTokens[i]]) return false;
        }
        return true;
    }

    /**
     * @notice Check whether ratio is valid
     */

    function _checkValidRatio(
        uint256[] calldata _ratio
    ) internal pure returns (bool) {
        uint256 totalRatio;

        for (uint256 i = 0; i < _ratio.length; i++) {
            totalRatio = totalRatio.add(_ratio[i]);
        }
        if (totalRatio != RATIO_DIVISOR) return false;
        return true;
    }

    /* ========== FALLBACK FUNCTIONS ========== */

    /**
     * @dev Only WETH contract is allowed to transfer ETH here.
     *      Prevent other addresses to send Ether to this contract.
     */
    receive() external payable {
        require(msg.sender == address(weth), "Receive not allowed");
    }

    /**
     * @dev Revert fallback calls
     */
    fallback() external payable {
        revert("Fallback not allowed");
    }

    /* ========== FLASHLOAN EXECUTE OPERATION ========== */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool) {
        /********************/
        /* Custom Logic Goes Here */
        /********************/
        require(msg.sender == address(POOL), "Only lending pool can call");
        require(initiator == address(this), "Invalid flashloan initiator");

        (address originalCaller, uint256 leverage) = abi.decode(
            params,
            (address, uint256)
        );

        for (uint256 i = 0; i < assets.length; i++) {
            gmxRewardRouter.mintAndStakeGlp(assets[i], amounts[i], 0, 0);
        }

        uint256 glpAmount = IERC20(glpToken).balanceOf(address(this));

        pool.supply(glpToken, glpAmount, originalCaller, 0);

        emit LeveragedGlpPosition(originalCaller, leverage, glpAmount);

        /********************/
        /* Custom Ends Goes Here */
        /********************/

        // for (uint i = 0; i < assets.length; i++) {
        //     uint amountOwing = amounts[i].add(premiums[i]);
        //     IERC20(assets[i]).safeApprove(address(POOL), amountOwing);
        // }

        return true;
    }
}

