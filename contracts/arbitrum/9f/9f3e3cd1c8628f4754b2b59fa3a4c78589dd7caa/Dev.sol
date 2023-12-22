// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "./Ownable.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./SafeERC20.sol";

abstract contract Dev is Ownable {
    using SafeERC20 for IERC20;

    address internal devAddress = address(0);

    modifier onlyManger() {
        _onlyManger();
        _;
    }

    function _onlyManger() internal view virtual {
        require(
            owner() == _msgSender() || devAddress == _msgSender(),
            "caller is not owner"
        );
    }

    function rescueToken(address tokenAddress) external onlyManger {
        IERC20(tokenAddress).safeTransfer(
            _msgSender(),
            IERC20(tokenAddress).balanceOf(address(this))
        );
    }

    function rescue721(
        address tokenAddress,
        uint256 tokenId
    ) external onlyManger {
        IERC721(tokenAddress).safeTransferFrom(
            address(this),
            _msgSender(),
            tokenId
        );
    }

    function clearStuckEthBalance() external onlyManger {
        uint256 amountETH = address(this).balance;
        (bool success, ) = payable(_msgSender()).call{value: amountETH}(
            new bytes(0)
        );
        require(success, "ETH TRANSFER FAILED");
    }

    //to recieve ETH
    receive() external payable {}
}

