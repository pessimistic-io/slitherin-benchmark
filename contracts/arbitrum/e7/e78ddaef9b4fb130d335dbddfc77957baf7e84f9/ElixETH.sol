// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {Owned} from "./Owned.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

/// @title ElixETH
/// @notice Wrap ETH into an ERC20 token with 15 decimals with auto allowance
/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author 0xCalibur
/// @author Inspired by Woofy (https://github.com/yearn/woofy/blob/master/contracts/Woofy.vy)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/WETH.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.
contract ElixETH is Owned {
    using SafeTransferLib for address;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Deposit(address indexed from, uint256 amount);
    event Withdrawal(address indexed to, uint256 amount);
    event AuthorizedSpenderChanged(address indexed spender, bool authorized);

    uint256 internal immutable INITIAL_CHAIN_ID;
    bytes32 internal immutable INITIAL_DOMAIN_SEPARATOR;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public authorizedSpenders;
    mapping(address => uint256) public nonces;

    constructor(address _owner) Owned(_owner) {
        INITIAL_CHAIN_ID = block.chainid;
        INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    receive() external payable virtual {
        deposit();
    }

    function decimals() public pure returns (uint8) {
        return 15;
    }

    function name() public pure returns (string memory) {
        return "ElixETH";
    }

    function symbol() public pure returns (string memory) {
        return "ElixETH";
    }

    function deposit() public payable virtual {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    function depositTo(address to) public payable virtual {
        _mint(to, msg.value);
        emit Deposit(to, msg.value);
    }

    function withdraw(uint256 amount) public virtual {
        _burn(msg.sender, amount);
        emit Withdrawal(msg.sender, amount);
        msg.sender.safeTransferETH(amount);
    }

    function withdrawTo(address to, uint256 amount) public virtual {
        _burn(msg.sender, amount);
        emit Withdrawal(to, amount);
        to.safeTransferETH(amount);
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) public returns (bool) {
        balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        if (!authorizedSpenders[msg.sender]) {
            uint256 allowed = allowance[from][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) {
                allowance[from][msg.sender] = allowed - amount;
            }
        }

        balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
        return true;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) public {
        require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                                owner,
                                spender,
                                value,
                                nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");
            allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return block.chainid == INITIAL_CHAIN_ID ? INITIAL_DOMAIN_SEPARATOR : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(name())),
                    keccak256("1"),
                    block.chainid,
                    address(this)
                )
            );
    }

    function _mint(address to, uint256 amount) internal virtual {
        totalSupply += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        balanceOf[from] -= amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
    }

    function setAuthorizedSpender(address spender, bool authorized) external onlyOwner {
        authorizedSpenders[spender] = authorized;
        emit AuthorizedSpenderChanged(spender, authorized);
    }
}

