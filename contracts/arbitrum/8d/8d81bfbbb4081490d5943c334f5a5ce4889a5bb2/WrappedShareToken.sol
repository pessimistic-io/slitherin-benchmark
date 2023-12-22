// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.15;

import {ShareTokenBase, Authority} from "./ShareTokenBase.sol";

import {IERC20Metadata} from "./IERC20Metadata.sol";
import {SafeERC20} from "./SafeERC20.sol";

/// @notice Voting share token that wraps underlying.
/// @author Dinari (https://github.com/dinaricrypto/dinari-contracts/blob/main/contracts/tokens/WrappedShareToken.sol)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Wrapper.sol)
// slither-disable-next-line unimplemented-functions
contract WrappedShareToken is ShareTokenBase {
    using SafeERC20 for IERC20Metadata;

    IERC20Metadata public immutable underlying;

    uint256 public multiple;

    constructor(
        string memory _name,
        string memory _symbol,
        IERC20Metadata _underlying,
        uint256 _multiple,
        address _owner,
        Authority _authority
    ) ShareTokenBase(_name, _symbol, _underlying.decimals(), _owner, _authority) {
        underlying = _underlying;
        multiple = _multiple;
    }

    function depositFor(address account, uint256 amount) external virtual requiresAuth {
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        _mint(account, (amount * 1 ether) / multiple);
    }

    function withdrawTo(address account, uint256 amount) external virtual {
        _burn(msg.sender, amount);
        underlying.safeTransfer(account, (amount * multiple) / 1 ether);
    }
}

