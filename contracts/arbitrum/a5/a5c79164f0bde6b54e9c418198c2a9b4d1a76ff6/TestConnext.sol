/* solhint-disable no-inline-assembly */
pragma solidity ^0.8.19;

import { IERC20Upgradeable } from "./IERC20Upgradeable.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { IConnext } from "./IConnext.sol";

// we use solady for safe ERC20 functions because of dependency hell and casting requirement of SafeERC20 in OpenZeppelin; solady has zero deps.
import { SafeTransferLib } from "./SafeTransferLib.sol";

contract TestConnext is OwnableUpgradeable {
    address public token;
    address public connext;

    function initialize(address _token, address _connext) public initializer {
        __Ownable_init();
        token = _token;
        connext = _connext;
        _transferOwnership(msg.sender);
    }

    function _collect(address tokenAddress, address to) internal {
        if (tokenAddress == address(0)) {
            if (address(this).balance == 0) {
                return;
            }

            payable(to).transfer(address(this).balance);

            return;
        }

        SafeTransferLib.safeTransferAll(tokenAddress, to);
    }

    function collectTokens(address[] memory tokens, address to) public onlyOwner {
        for (uint i=0; i<tokens.length; i++) {
            _collect(tokens[i], to);
        }
    }

    function possiblyApprove(address spender, uint256 amount) internal {
        uint256 allowance = IERC20Upgradeable(token).allowance(address(this), spender);

        if (allowance > 0) {
            SafeTransferLib.safeApprove(token, spender, 0);
        }

        if (amount == 0) {
            return;
        }

        SafeTransferLib.safeApprove(token, spender, amount);
    }

    function withdraw(uint256 amount, uint32 destinationDomain, uint256 relayerFee) payable public {
        possiblyApprove(connext, amount);

        bytes memory callData;
        IConnext(connext).xcall{value: relayerFee}(
            destinationDomain, // _destination: Domain ID of the destination chain
            msg.sender,        // _to: address of the target contract
            address(token),    // _asset: address of the token contract
            msg.sender,        // _delegate: address that can revert or forceLocal on destination
            amount,            // _amount: amount of tokens to transfer
            uint256(300),          // _slippage: max slippage the user will accept in BPS (e.g. 300 = 3%)
            callData           // _callData: the encoded calldata to send
        );

        SafeTransferLib.safeApprove(address(token), connext, 0);
    }
}

