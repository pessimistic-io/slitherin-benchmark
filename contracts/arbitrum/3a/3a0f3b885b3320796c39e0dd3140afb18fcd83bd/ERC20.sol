// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @notice ERC20 contract for use with ennead contracts only!
 * @notice follows the ERC20 standard, based on OpenZeppelin implementation
 */

contract ERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    bytes32 internal DOMAIN_SEPARATOR;
    bytes32 internal constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint256) public nonces;

    event Transfer(address indexed from, address indexed to, uint amount);

    event Approval(address indexed owner, address indexed spender, uint amount);

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(amount > 0, "Can't transfer 0!");

        beforeTokenTransfer(from, to);
        balanceOf[from] -= amount;

        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        require(
            allowance[from][msg.sender] >= amount,
            "Insufficient allowance"
        );
        if (allowance[from][msg.sender] != type(uint256).max)
            allowance[from][msg.sender] -= amount;

        _transfer(from, to, amount);
        return true;
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal virtual {
        unchecked {
            totalSupply += amount;
            balanceOf[to] += amount;
        }
        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "ERC20: EXPIRED");
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(
                    abi.encode(
                        PERMIT_TYPEHASH,
                        owner,
                        spender,
                        value,
                        nonces[owner]++,
                        deadline
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(
            recoveredAddress != address(0) && recoveredAddress == owner,
            "ERC20: INVALID_SIGNATURE"
        );
        allowance[owner][spender] = value;

        emit Approval(owner, spender, value);
    }

    function beforeTokenTransfer(address from, address to) internal virtual {}
}

