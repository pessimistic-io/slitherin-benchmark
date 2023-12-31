// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;
import "./IERC20.sol";
import "./draft-ERC20Permit.sol";
import "./ISwapRouter02.sol";
import "./SwapV3.sol";
import "./MyPausable.sol";
import "./BlackList.sol";
import "./Fee.sol";
import "./Mint.sol";

contract BOBOCoin is ERC20Permit, MyPausable, BlackList, Fee, SwapV3, Mint {
    event Transfer2(
        address msgSender,
        address from,
        address to,
        uint256 amount
    );

    constructor(
        address devAddress_,
        ISwapRouter02 swapRouter_,
        INonfungiblePositionManager positionManager_,
        address _chainLinkEth
    )
        ERC20("BOBO", "BOBO")
        ERC20Permit("BOBO")
        SwapV3(swapRouter_, positionManager_, _chainLinkEth)
    {
        devAddress = devAddress_;
        _addExcludeFromFee(address(this));
        _addExcludeFromFee(owner());
        _addExcludeFromFee(devAddress);

        _mint(msg.sender, 210_000_000_000_000_000_000_000);
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function burn(address account, uint256 amount) public onlyManger {
        _burn(account, amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        emit Transfer2(_msgSender(), sender, recipient, amount);
        if (inSwap) {
            super._transfer(sender, recipient, amount);
            return;
        }
        require(!getBlackListStatus(sender), "operator in blacklist");
        require(!getBlackListStatus(recipient), "recipient in blacklist");
        amount = _tokenTransferHandle(sender, recipient, amount);
        super._transfer(sender, recipient, amount);
    }

    function _tokenTransferHandle(
        address from,
        address to,
        uint256 amount
    ) internal returns (uint256 actualAmount) {
        actualAmount = amount;
        bool isExclude = isExcludeFromFee(from) || isExcludeFromFee(to);
        if (_isLpOpt(from, to)) {
            require(
                isExclude || swapEnable || isRouter(from) || isRouter(to),
                "trade not start yet"
            );
            return actualAmount;
        }
        if (!isExclude) {
            require(swapEnable, "trade not start yet");
            _requireNotPaused();
        }
        _doClaim();
        if (isPair(from) || isPair(to)) {
            if (!isExclude && isPair(from)) {
                actualAmount = _transferFromSwap(
                    from,
                    to,
                    amount,
                    isPair(from) ? 1 : 2
                );
            }
        } else {
            if (swapEnable) {
                _taxSwap();
            }
        }
    }

    function _innerTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._transfer(from, to, amount);
    }
}

