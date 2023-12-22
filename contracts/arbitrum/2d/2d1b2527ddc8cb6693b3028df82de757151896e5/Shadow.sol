// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "./IERC1155.sol";
import "./IERC20.sol";
import "./IERC20Metadata.sol";
import "./IERC1155Supply.sol";

import "./IShadowFactory.sol";

contract Shadow is IERC20, IERC20Metadata {
    address public immutable FACTORY;

    mapping(address => mapping(address => uint256)) private s_allowances;

    constructor(address factory) {
        require(factory != address(0), "Shadow: Address Zero");
        FACTORY = factory;
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        if (!IERC1155(FACTORY).isApprovedForAll(msg.sender, spender)) {
            _approve(msg.sender, spender, amount);
        }
        return true;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        require(to != address(0), "ERC20: transfer to the zero address");
        IShadowFactory(FACTORY).safeTransferFromByShadow(
            msg.sender,
            to,
            ID(),
            amount
        );
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        require(to != address(0), "ERC20: transfer to the zero address");
        _spendAllowance(from, msg.sender, amount);
        IShadowFactory(FACTORY).safeTransferFromByShadow(
            from,
            to,
            ID(),
            amount
        );
        emit Transfer(from, to, amount);
        return true;
    }

    function increaseAllowance(
        address spender,
        uint256 addedValue
    ) public virtual returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        if (currentAllowance != type(uint256).max) {
            _approve(msg.sender, spender, currentAllowance + addedValue);
        }
        return true;
    }

    function decreaseAllowance(
        address spender,
        uint256 subtractedValue
    ) public virtual returns (bool) {
        uint256 currentAllowance = allowance(msg.sender, spender);
        require(
            currentAllowance >= subtractedValue,
            "ERC20: insufficient allowance"
        );
        unchecked {
            _approve(msg.sender, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function name() public view virtual override returns (string memory) {
        return IShadowFactory(FACTORY).getShadowName(ID());
    }

    function symbol() public view virtual override returns (string memory) {
        return IShadowFactory(FACTORY).getShadowSymbol(ID());
    }

    function decimals() public view virtual override returns (uint8) {
        return IShadowFactory(FACTORY).getShadowDecimals(ID());
    }

    function totalSupply() public view override returns (uint256) {
        return IERC1155Supply(FACTORY).totalSupply(ID());
    }

    function balanceOf(address account) public view override returns (uint256) {
        return IERC1155(FACTORY).balanceOf(account, ID());
    }

    function allowance(
        address owner,
        address spender
    ) public view virtual override returns (uint256) {
        if (IERC1155(FACTORY).isApprovedForAll(owner, spender)) {
            return type(uint256).max;
        }
        return s_allowances[owner][spender];
    }

    /// @notice Returns the metadata of this (MetaProxy) contract.
    /// Only relevant with contracts created via the MetaProxy standard.
    /// @dev This function is aimed to be invoked with- & without a call.
    function ID() public pure returns (uint256 id) {
        assembly {
            id := calldataload(sub(calldatasize(), 32))
        }
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        s_allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= amount,
                "ERC20: insufficient allowance"
            );
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }
}

