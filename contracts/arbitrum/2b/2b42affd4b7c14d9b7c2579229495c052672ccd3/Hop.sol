// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./bridge.sol";
import "./amm.sol";
import "./errors.sol";
import "./ImplBase.sol";

/**
// @title HOP L2 Implementation.
// @notice This is the L2 implementation, so this is used when transferring from l2
// to supported l2s or L1.
// Called by the registry if the selected bridge is Hop Bridge.
// @dev Follows the interface of ImplBase.
// @author Movr Network.
*/
contract HopImplL2 is ImplBase, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice constructor only required resistry address.
    constructor(address _registry) ImplBase(_registry) {}

    /**
    // @notice Function responsible for cross chain transfer from l2 to l1 or supported
    // l2s.
    // Called by the registry when the selected bridge is Hop bridge.
    // @dev Try to check for the liquidity on the other side before calling this.
    // @param _amount amount to be sent.
    // @param _from sender address
    // @param _receiverAddress receiver address
    // @param _toChainId Destination Chain Id
    // @param _token address of the token to bridged to the destination chain. 
    // @param _data data required to call the Hop swap and send function. hopAmm address,
    // boderfee, amount out min and deadline.
    */
    function outboundTransferTo(
        uint256 _amount,
        address _from,
        address _receiverAddress,
        address _token,
        uint256 _toChainId,
        bytes memory _data
    ) external payable override onlyRegistry nonReentrant {
        // decode data
        (
            address _hopAMM,
            uint256 _bonderFee, // fees passed to relayer
            uint256 _amountOutMin,
            uint256 _deadline,
            address _tokenAddress
        ) = abi.decode(_data, (address, uint256, uint256, uint256, address));
        // token address might not be indication thats why passed through extraData
        if (_tokenAddress == NATIVE_TOKEN_ADDRESS) {
            require(msg.value != 0, MovrErrors.VALUE_SHOULD_NOT_BE_ZERO);
            // perform bridging
            HopAMM(_hopAMM).swapAndSend{value: _amount}(
                _toChainId,
                _receiverAddress,
                _amount,
                _bonderFee,
                _amountOutMin,
                _deadline,
                _amountOutMin,
                _deadline
            );
            return;
        }
        require(msg.value == 0, MovrErrors.VALUE_SHOULD_BE_ZERO);
        IERC20(_token).safeTransferFrom(_from, address(this), _amount);
        IERC20(_token).safeIncreaseAllowance(_hopAMM, _amount);

        // perform bridging
        HopAMM(_hopAMM).swapAndSend(
            _toChainId,
            _receiverAddress,
            _amount,
            _bonderFee,
            _amountOutMin,
            _deadline,
            _amountOutMin,
            _deadline
        );
    }
}

