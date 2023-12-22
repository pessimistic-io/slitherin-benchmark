//SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";

/**
// @title Abstract Contract for protocol adapter.
// @notice All adapters will follow this interface.
*/
abstract contract AdapterBase {
    using SafeERC20 for IERC20;
    address internal constant NATIVE = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public router;
    event GovernanceTransfer(address indexed from, address indexed to);

    /**
    * @dev Throws if called by any account other than the router.
    */
    modifier onlyDispatcher {
        require(router == msg.sender, "UNAUTHORIZED");
        _;
    }

    constructor(address _router) {
        require(_router != address(0), "ZERO_ADDRESS_FORBIDDEN");
        router = _router;
    }

    /**
    // @dev Allows to receive ether
    */
    receive() external payable {}

    /**
    // @dev Generic function to call swap protocol
    // @param _fromToken input token address
    // @param _fromAmount input token amount
    // @param _toToken output token address
    // @param _swapCallData swap callData (intended for one specific protocol)
    */
    function callAction(address fromUser, address _fromToken, uint256 _fromAmount, address _toToken, bytes memory _swapCallData) public payable virtual returns (uint256 toAmount);

    // onlyRouter functions

    /**
    // @dev Transfers funds to chosen recipient
    // @param token token address
    // @param recipient recipient of the transfer
    // @param amount amount to transfer
    */
    function rescueFunds(
    address token,
    address recipient,
    uint256 amount
    ) external onlyDispatcher {
        if (token != NATIVE) {
            IERC20(token).safeTransfer(recipient, amount);
        } else {
            payable(recipient).transfer(amount);
        }
    }

    /**
    // @dev Transfer governance to another contract
    // @dev set a new value for router
    // @param _newRouter address of the new governance contract
    */
    function transferGovernance(address _newRouter) public onlyDispatcher {
        require(_newRouter != address(0), "ZERO_ADDRESS_FORBIDDEN");
        router = _newRouter;
        emit GovernanceTransfer(msg.sender, _newRouter);
    }
}

