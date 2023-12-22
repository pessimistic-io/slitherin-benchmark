// SPDX-License-Identifier: MIT

pragma solidity 0.8.15;

import "./IERC20.sol";

library TransferHelper {
    function transferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        if (from == address(this)) {
            (bool success, ) = token.call(
                abi.encodeWithSelector(IERC20.transfer.selector, to, value)
            );
            require(success, "TH1");
        } else {
            (bool success, ) = token.call(
                abi.encodeWithSelector(
                    IERC20.transferFrom.selector,
                    from,
                    to,
                    value
                )
            );
            require(success, "TH2");
        }
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                from,
                to,
                value
            )
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TH3"
        );
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TH4"
        );
    }

    function approve(
        address token,
        address to,
        uint256 value
    ) internal {
        (bool success,) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, to, value)
        );
        require(
            success ,
            "TH5"
        );
    }

    function transferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "TH6");
    }
}

