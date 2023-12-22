// SPDX-License-Identifier: MIT



pragma solidity 0.8.19;

import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "./ReentrancyGuardUpgradeable.sol";

import {IERC20Metadata} from "./IERC20Metadata.sol";

import {GMXAdapter} from "./GMXAdapter.sol";

import {Events} from "./Events.sol";
import {Errors} from "./Errors.sol";

import {IAdaptersRegistry} from "./IAdaptersRegistry.sol";
import {IContractsFactory} from "./IContractsFactory.sol";
import {IDynamicValuation} from "./IDynamicValuation.sol";
import {IAdapter} from "./IAdapter.sol";
import {IBaseVault} from "./IBaseVault.sol";
import {IGmxVault} from "./IGmxVault.sol";
import {IERC20} from "./ERC20_IERC20.sol";

abstract contract BaseVault is
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IBaseVault,
    Errors,
    Events
{
    uint256 public constant BASE = 1e18; // 100%
    address public override underlyingTokenAddress;
    address public override contractsFactoryAddress;

    uint256 public override currentRound;

    uint256 public override afterRoundBalance;

    uint256 internal _ONE_UNDERLYING_TOKEN;

    modifier notZeroAddress(address _variable, string memory _message) {
        _checkZeroAddress(_variable, _message);
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function __BaseVault_init(
        address _underlyingTokenAddress,
        address _ownerAddress
    ) internal onlyInitializing {
        __Ownable_init();
        __ReentrancyGuard_init();

        __BaseVault_init_unchained(_underlyingTokenAddress, _ownerAddress);
    }

    function __BaseVault_init_unchained(
        address _underlyingTokenAddress,
        address _ownerAddress
    ) internal onlyInitializing {
        _checkZeroAddress(_underlyingTokenAddress, "_underlyingTokenAddress");
        _checkZeroAddress(_ownerAddress, "_ownerAddress");

        _ONE_UNDERLYING_TOKEN =
            10 ** IERC20Metadata(_underlyingTokenAddress).decimals();

        underlyingTokenAddress = _underlyingTokenAddress;
        contractsFactoryAddress = msg.sender;

        transferOwnership(_ownerAddress);

        // THIS LINE IS COMMENTED JUST TO DEPLOY ON GOERLI WHERE THERE ARE NO GMX CONTRACTS
        GMXAdapter.__initApproveGmxPlugin();
    }

    receive() external payable {}

    /* OWNER FUNCTIONS */

    /* INTERNAL FUNCTIONS */

    function _executeOnAdapter(
        address _adapterAddress,
        bool _isTraderWallet,
        address _traderWallet,
        address _usersVault,
        uint256 _ratio,
        IAdapter.AdapterOperation memory _traderOperation
    ) internal returns (uint256) {
        (bool success, uint256 ratio) = IAdapter(_adapterAddress)
            .executeOperation(
                _isTraderWallet,
                _traderWallet,
                _usersVault,
                _ratio,
                _traderOperation
            );
        if (!success) revert AdapterOperationFailed(_adapterAddress);
        return ratio;
    }

    function _executeOnGmx(
        bool _isTraderWallet,
        address _traderWallet,
        address _usersVault,
        uint256 _ratio,
        IAdapter.AdapterOperation memory _traderOperation
    ) internal returns (uint256) {
        (bool success, uint256 ratio) = GMXAdapter.executeOperation(
            _isTraderWallet,
            _traderWallet,
            _usersVault,
            _ratio,
            _traderOperation
        );
        if (!success) revert AdapterOperationFailed(address(0));
        return ratio;
    }

    function _getAdapterAddress(
        uint256 _protocolId
    ) internal view returns (address) {
        (bool adapterExist, address adapterAddress) = IAdaptersRegistry(
            IContractsFactory(contractsFactoryAddress).adaptersRegistryAddress()
        ).getAdapterAddress(_protocolId);
        if (!adapterExist || adapterAddress == address(0))
            revert InvalidAdapter();

        return adapterAddress;
    }

    function _convertTokenAmountToUnderlyingAmount(
        address token,
        uint256 amount
    ) internal view returns (uint256 underlyingTokenAmount) {
        address _underlyingTokenAddress = underlyingTokenAddress;
        if (token == _underlyingTokenAddress) {
            return amount;
        }

        address _contractsFactoryAddress = contractsFactoryAddress;
        address dynamicValuationAddress = IContractsFactory(
            _contractsFactoryAddress
        ).dynamicValuationAddress();

        uint256 ONE_UNDERLYING_TOKEN = _ONE_UNDERLYING_TOKEN;

        uint256 tokenPrice = IDynamicValuation(dynamicValuationAddress)
            .getOraclePrice(token, amount);
        uint256 underlyingPrice = IDynamicValuation(dynamicValuationAddress)
            .getOraclePrice(_underlyingTokenAddress, ONE_UNDERLYING_TOKEN);

        return (tokenPrice * ONE_UNDERLYING_TOKEN) / underlyingPrice;
    }

    function _checkZeroRound() internal view {
        if (currentRound == 0) revert InvalidRound();
    }

    function _checkZeroAddress(
        address _variable,
        string memory _message
    ) internal pure {
        if (_variable == address(0)) revert ZeroAddress({target: _message});
    }

    // @todo consider adding TimeLock for this function?
    /// @notice Withdrawing tokens in the emergency case from the contract
    /// @dev Danger! Use this only in emergency case. Otherwise it can brake contract logic.
    /// @param token The token address to be withdrawn
    function emergencyWithdraw(IERC20 token) external onlyOwner {
        if (address(token) == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) {
            uint256 ethBalance = address(this).balance;
            payable(owner()).transfer(ethBalance);
            return;
        }
        uint256 balance = token.balanceOf(address(this));
        token.transfer(owner(), balance);
    }

    /// @notice Decrease/close position in emergency case
    /// @dev Danger! Use this only in emergency case. Otherwise it can brake contract logic.
    /// @param path The swap path [collateralToken] or [collateralToken, tokenOut] if a swap is needed
    /// @param indexToken The address of the token that was longed (or shorted)
    /// @param sizeDelta The USD value of the change in position size (scaled to 1e30).
    ///                  To close position use current position's 'size'
    /// @param isLong Whether the position is a long or short
    function emergencyDecreasePosition(
        address[] calldata path,
        address indexToken,
        uint256 sizeDelta,
        bool isLong
    ) external onlyOwner {
        GMXAdapter.emergencyDecreasePosition(
            path,
            indexToken,
            sizeDelta,
            isLong
        );
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}

