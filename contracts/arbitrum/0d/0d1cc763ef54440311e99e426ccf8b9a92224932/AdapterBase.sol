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
    uint16 public feeRateBps;
    event GovernanceTransfer(address indexed from, address indexed to);
    event FeeRateChange(uint16 indexed newFeeRateBps);
    event Swap(address indexed fromWallet, address indexed inputToken, uint256 inputTokenAmount, address indexed outputToken, uint256 returnAmount);

    /**
    * @dev Throws if called by any account other than the router.
    */
    modifier onlyDispatcher {
        require(router == msg.sender, "UNAUTHORIZED");
        _;
    }

    constructor(address _router) {
        router = _router;
    }

    /**
    // @dev allows to receive ether
    */
    receive() external payable {}

    /**
    // @dev generic function to call swap protocol
    // @param _inputToken input token address
    // @param _inputTokenAmount input token amount
    // @param _outputToken output token address
    // @param _swapCallData swap callData (intended for one specific protocol)
    */
    function callAction(address fromUser, address _inputToken, uint256 _inputTokenAmount, address _outputToken, bytes memory _swapCallData) public payable virtual;

    /**
    // @dev utility to compute fee for a given amount
    // @param amount input token address
    */
    function computeFee(uint256 amount) public view returns (uint) {
        return (5000 + (amount * feeRateBps)) / 10000;
    }

    // onlyRouter functions

    /**
    // @dev set fee rate
    // @param _feeRateBps fee rate in bps
    */
    function setFeeRate(uint16 _feeRateBps) public onlyDispatcher {
        feeRateBps = _feeRateBps;
        emit FeeRateChange(_feeRateBps);
    }

    /**
    // @dev transfer funds to chosen recipient
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
    // @dev transfer governance to another contract
    // @dev set a new value for router
    // @param _newGovernance address of the new governance contract
    */
    function transferGovernance(address _newGovernance) public onlyDispatcher {
        require(_newGovernance != address(0), "ZERO_ADDRESS_FORBIDDEN");
        router = _newGovernance;
        emit GovernanceTransfer(msg.sender, _newGovernance);
    }
}
