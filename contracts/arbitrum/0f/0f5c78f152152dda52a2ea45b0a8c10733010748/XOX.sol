// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./XOXArbitrumBase.sol";
import "./Address.sol";

contract XOXTokenArbitrum is XOXArbitrumBase {
    using Address for address;

    address private _minter;

    constructor(
        address timelockAdmin_,
        address timelockSystem_,
        address feeWallet_,
        address uniswapV2Router_,
        uint256 timeStartTrade_
    )
        XOXArbitrumBase(
            "XOX Labs",
            "XOX",
            18,
            timelockSystem_,
            feeWallet_,
            uniswapV2Router_,
            timeStartTrade_
        )
    {
        require(timelockAdmin_.isContract(), "XOXToken: timelock is smartcontract");
        _transferOwnership(timelockAdmin_);
        _minter = timelockSystem_;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyMinter() {
        require(_minter == _msgSender(), "XOXToken: caller is not the minter");
        _;
    }

    function mint(
        address account,
        uint256 amount,
        bytes32 txSource,
        uint256 chainIdSource
    ) external onlyMinter {
        _mint(account, amount, txSource, chainIdSource);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnBridge(
        address account,
        uint256 amount,
        uint256 chainId
    ) external {
        _burnBridge(msg.sender, account, amount, chainId);
    }

    function transferMinter(address minter_) external onlyOwner {
        require(minter_.isContract(), "XOXToken: minter is a smartcontract");
        _minter = minter_;
        emit MintershipTransferred(_minter, minter_);
    }

    event MintershipTransferred(
        address indexed previousMinter,
        address indexed newMinter
    );

    function changeTaxFee(uint256 taxFee_) external onlyOwner {
        _changeTaxFee(taxFee_);
    }

    function changeFeeWallet(address feeWallet) external onlyOwner {
        _changeFeeWallet(feeWallet);
    }

    function changeSwapPath(address[] memory path_, address[] memory poolsPath_) external onlyOwner {
        _changeSwapPath(path_, poolsPath_);
    }

    function setSwapAndLiquifyEnabled(
        bool swapAndLiquifyEnabled_
    ) external onlyOwner {
        _setSwapAndLiquifyEnabled(swapAndLiquifyEnabled_);
    }
}

