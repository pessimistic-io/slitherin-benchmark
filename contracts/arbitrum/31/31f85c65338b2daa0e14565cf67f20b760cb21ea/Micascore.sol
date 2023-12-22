// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import {Initializable} from "./Initializable.sol";
import {AccessControlUpgradeable} from "./AccessControlUpgradeable.sol";
import {IERC20Upgradeable} from "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";

contract Micascore is Initializable, AccessControlUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;
    AggregatorV3Interface internal priceFeed;

    bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");
    uint32 public constant DECIMALS_USD = 10 ** 6;
    uint64 public constant DECIMALS_NATIVE_TOKEN = 10 ** 18;
    IERC20Upgradeable public USDTtokenAddress;
    IERC20Upgradeable public USDCtokenAddress;
    uint256[] public actionIDs;

    mapping(uint256 => uint256) private _actionTypeFees; // actionID ->_stableUSDFee
    address payable private _collectorWallet;

    event ActionTypeSwitched(bool feeActionTypeOracleEnabled);
    event ActionFeeAndIDSet(uint256 actionID, uint256 actionFee);
    event ActionFeeAndIDRemoved(uint256 actionID);
    event AggregatorChanged(address newAggregatorAddress);
    event CollectorSet(address collectorWallet);
    event FeeSet(uint256 newFee);
    event FeePaid(address assetAddress, uint256 actionID, uint256 amount);

    error ErrorSendingTokens();
    error NotEnoughTokenAllowance();
    error NonExistantActionID();
    error NonExistingFeePayment();
    error PassedAmountNotExact();
    error ZeroAddress();
    error ZeroFeeAmount();

    modifier mNotZero(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    modifier mFeeNotZero(uint256 amount) {
        if (amount == 0) revert ZeroFeeAmount();
        _;
    }

    function initialize(
        address aggregatorAddress,
        address collectorWallet,
        IERC20Upgradeable USDTaddress,
        IERC20Upgradeable USDCaddress,
        uint256[] memory actionID,
        uint256[] memory feeAmountUSD
    ) external virtual initializer {
        priceFeed = AggregatorV3Interface(aggregatorAddress);
        _collectorWallet = payable(collectorWallet);

        USDTtokenAddress = USDTaddress;
        USDCtokenAddress = USDCaddress;

        for (uint256 index = 0; index < actionID.length; index++) {
            _actionTypeFees[actionID[index]] = feeAmountUSD[index];
            actionIDs.push(actionID[index]);
        }

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MANAGER_ROLE, msg.sender);
    }

    // ------- CORE FUNCTIONS -------
    function payFee(address assetAddress, uint256 actionID) external payable {
        if (_actionTypeFees[actionID] == 0) revert NonExistantActionID();
        if (assetAddress == address(USDTtokenAddress)) {
            _payFeeWithERC20(USDTtokenAddress, actionID);
        } else if (assetAddress == address(USDCtokenAddress)) {
            _payFeeWithERC20(USDCtokenAddress, actionID);
        } else if (assetAddress == address(0)) {
            uint256 nativeCurrencyAmount = getOracleFee(actionID);

            if (msg.value < nativeCurrencyAmount)
                revert PassedAmountNotExact();

            // solhint-disable-next-line avoid-low-level-calls
            (bool success, ) = payable(_collectorWallet).call{
                gas: 200_000,
                value: nativeCurrencyAmount
            }("");

            if (!success) revert ErrorSendingTokens();
            emit FeePaid(assetAddress, actionID, nativeCurrencyAmount);
        } else {
            revert NonExistingFeePayment();
        }
    }

    // ------- SETTER FUNCTIONS -------
    function setCollectorWallet(
        address payable collectorWallet
    ) public onlyRole(MANAGER_ROLE) mNotZero(collectorWallet) {
        _collectorWallet = collectorWallet;
        emit CollectorSet(_collectorWallet);
    }

    function setPriceFeed(
        address newAggregatorAddress
    ) public onlyRole(MANAGER_ROLE) mNotZero(newAggregatorAddress) {
        priceFeed = AggregatorV3Interface(newAggregatorAddress);
        emit AggregatorChanged(newAggregatorAddress);
    }

    function setActionFeeAndID(
        uint256 actionID,
        uint256 actionFee
    ) public onlyRole(MANAGER_ROLE) mFeeNotZero(actionFee) {
        _actionTypeFees[actionID] = actionFee;
        actionIDs.push(actionID);
        emit ActionFeeAndIDSet(actionID, actionFee);
    }

    function removeActionFee(uint256 actionID) public onlyRole(MANAGER_ROLE) {
        for (uint256 index = 0; index < actionIDs.length; index++) {
            if (actionIDs[index] == actionID) {
                delete actionIDs[index];
                continue;
            }
        }
        delete _actionTypeFees[actionID];
        emit ActionFeeAndIDRemoved(actionID);
    }

    // ------- GETTER FUNCTIONS -------
    function getCollectorWallet() public view returns (address) {
        return _collectorWallet;
    }

    function getActionTypeFee(uint256 actionID) public view returns (uint256) {
        return _actionTypeFees[actionID];
    }

    function getOracleFee(
        uint256 actionID
    ) public view virtual returns (uint256 oracleFee) {
        // Retrieves ETH/USD
        (
            ,
            /*uint80 roundID*/
            int256 price /*uint startedAt*/ /*uint timeStamp*/ /*uint80 answeredInRound*/,
            ,
            ,

        ) = priceFeed.latestRoundData();

        // Calculate price for 1 ETH and
        // Calculate how much ETH will it cost to cover the fee set in USD
        oracleFee =
            _actionTypeFees[actionID] * 10 ** priceFeed.decimals() /
                uint(int(price)) * DECIMALS_NATIVE_TOKEN /
            DECIMALS_USD;

        // Return the price for 1 USD in Native token
        return oracleFee;
    }

    // ------- INTERNAL FUNCTIONS -------
    function _payFeeWithERC20(
        IERC20Upgradeable tokenAddress,
        uint256 actionID
    ) internal virtual {
        if (
            tokenAddress.allowance(msg.sender, address(this)) <
            _actionTypeFees[actionID]
        ) revert NotEnoughTokenAllowance();

        tokenAddress.safeTransferFrom(
            msg.sender,
            _collectorWallet,
            _actionTypeFees[actionID]
        );
        emit FeePaid(
            address(tokenAddress),
            actionID,
            _actionTypeFees[actionID]
        );
    }
}

