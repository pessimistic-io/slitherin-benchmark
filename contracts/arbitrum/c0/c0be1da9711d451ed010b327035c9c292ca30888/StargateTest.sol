// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.4;


import "./Ownable.sol";
import "./IERC20.sol";
import "./IStargateRouter.sol";

contract StargateTest is Ownable {

    struct CrossSwapParams {
        uint16 dstChainId;
        uint256 srcPoolId;
        address srcToken;
        uint256 dstPoolId;
        uint256 amountLD;
        uint256 minAmountLD;
        uint256 gas;
        address dstContract;
    }

    event Record(
        uint256 gasUsed
    );

    address public stargateComposer;
    address public sgeth;

    receive() external payable {}

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'STE');
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'ST');
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'STF');
    }

    constructor(address _stargateComposer, address _sgeth) {
        stargateComposer = _stargateComposer;
        sgeth = _sgeth;
    }

    function setStargateComposer(address _stargateComposer) onlyOwner external {
        stargateComposer = _stargateComposer;
    }

    function setSgeth(address _sgeth) onlyOwner external {
        sgeth = _sgeth;
    }

    function srcDeposit(address token, uint256 amount) internal {
        if (token == address(0)) {
            require(msg.value > amount, "msg value not enough");
        } else {
            safeTransferFrom(token, msg.sender, address(this), amount);
        }
    }

    function crossSwap(CrossSwapParams calldata params) external payable {
        srcDeposit(params.srcToken, params.amountLD);
        if (params.srcToken != address(0)) {
            IERC20(params.srcToken).approve(
                stargateComposer,
                params.amountLD
            );
        }
        bytes memory payload = abi.encode(msg.sender);
        IStargateRouter(stargateComposer).swap{value: address(this).balance}(
            params.dstChainId,
            params.srcPoolId,
            params.dstPoolId,
            payable(msg.sender), // refund address
            params.amountLD,
            params.minAmountLD,
            IStargateRouter.lzTxObj(
                params.gas,
                0,
                abi.encodePacked(params.dstContract)
            ),
            abi.encodePacked(params.dstContract),
            payload
        );
        if (params.srcToken != address(0)) {
            IERC20(params.srcToken).approve(
                stargateComposer,
                0
            );
        }
    }

    function sgReceive(
        uint16,
        bytes memory,
        uint256,
        address _token,
        uint256 amountLD,
        bytes memory payload
    ) external {
        uint256 gasLeft = gasleft();
        require(msg.sender == stargateComposer, "Not stargate composer!");
        (address recipient) = abi.decode(payload, (address));
        if (_token == sgeth) {
            safeTransferETH(recipient, address(this).balance);
        } else {
            safeTransfer(_token, recipient, amountLD);
        }
        emit Record(gasLeft - gasleft());
    }

}
