// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

// Pulled from https://github.com/gelatodigital/automate/blob/v2.1.0/contracts/integrations/AutomateReady.sol
// With minor changes to make it compatible with UUPSUpgradable contracts

import "./SafeERC20.sol";
import "./Types.sol";

/**
 * @dev Inherit this contract to allow your smart contract to
 * - Make synchronous fee payments.
 * - Have call restrictions for functions to be automated.
 */
// solhint-disable private-vars-leading-underscore
abstract contract AutomateReady {
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IAutomate public immutable automate;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable dedicatedMsgSender;

    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address private immutable _gelato;
    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address private constant OPS_PROXY_FACTORY =
        0xC815dB16D4be6ddf2685C201937905aBf338F5D7;

    /**
     * @dev
     * Only tasks created by _taskCreator defined in constructor can call
     * the functions with this modifier.
     */
    modifier onlyDedicatedMsgSender() {
        require(msg.sender == dedicatedMsgSender, "Only dedicated msg.sender");
        _;
    }

    /**
     * @dev
     * _taskCreator is the address which will create tasks for this contract.
     */
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address _automate, address _taskCreator) {
        automate = IAutomate(_automate);
        _gelato = IAutomate(_automate).gelato();
        (dedicatedMsgSender, ) = IOpsProxyFactory(OPS_PROXY_FACTORY).getProxyOf(
            _taskCreator
        );
    }

    /**
     * @dev
     * Transfers fee to gelato for synchronous fee payments.
     *
     * _fee & _feeToken should be queried from IAutomate.getFeeDetails()
     */
    function _transfer(uint256 _fee, address _feeToken) internal {
        if (_feeToken == ETH) {
            (bool success, ) = _gelato.call{value: _fee}("");
            require(success, "_transfer: ETH transfer failed");
        } else {
            SafeERC20.safeTransfer(IERC20(_feeToken), _gelato, _fee);
        }
    }

    function _getFeeDetails()
        internal
        view
        returns (uint256 fee, address feeToken)
    {
        (fee, feeToken) = automate.getFeeDetails();
    }
}

