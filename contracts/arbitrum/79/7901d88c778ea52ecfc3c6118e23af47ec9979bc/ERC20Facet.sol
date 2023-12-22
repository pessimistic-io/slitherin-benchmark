// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./ERC20Storage.sol";

import { Initializable } from "./Initializable.sol";

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Modified from Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/ERC20.sol)
abstract contract ERC20Facet is Initializable {
    ERC20Storage.ERC20DS private __storageLayout;
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Transfer(address indexed from, address indexed to, uint256 amount);

    event Approval(address indexed owner, address indexed spender, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    function __ERC20_init(string memory _name, string memory _symbol, uint8 _decimals) internal onlyInitializing {
        ERC20Storage.layout().name = _name;
        ERC20Storage.layout().symbol = _symbol;
        ERC20Storage.layout().decimals = _decimals;

        ERC20Storage.layout().INITIAL_CHAIN_ID = block.chainid;
        ERC20Storage.layout().INITIAL_DOMAIN_SEPARATOR = computeDomainSeparator();
    }

    /*//////////////////////////////////////////////////////////////
                               ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    function balanceOf(address account) public view virtual returns (uint256) {
        return ERC20Storage.layout().balanceOf[account];
    }

    function totalSupply() public view virtual returns (uint256) {
        return ERC20Storage.layout().totalSupply;
    }

    function name() public view virtual returns (string memory) {
        return ERC20Storage.layout().name;
    }

    function symbol() public view virtual returns (string memory) {
        return ERC20Storage.layout().symbol;
    }

    function decimals() public view virtual returns (uint256) {
        return ERC20Storage.layout().decimals;
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal virtual {
        uint256 currentAllowance = ERC20Storage.layout().allowance[msg.sender][spender];
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, 'ERC20: insufficient allowance');
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), 'ERC20: approve from the zero address');
        require(spender != address(0), 'ERC20: approve to the zero address');

        ERC20Storage.layout().allowance[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        ERC20Storage.layout().allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        _beforeTokenTransfer(msg.sender, to, amount);
        ERC20Storage.layout().balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            ERC20Storage.layout().balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);
        _afterTokenTransfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        _beforeTokenTransfer(from, to, amount);
        uint256 allowed = ERC20Storage.layout().allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) ERC20Storage.layout().allowance[from][msg.sender] = allowed - amount;

        ERC20Storage.layout().balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            ERC20Storage.layout().balanceOf[to] += amount;
        }

        emit Transfer(from, to, amount);
        _afterTokenTransfer(from, to, amount);

        return true;
    }

    /*//////////////////////////////////////////////////////////////
                             EIP-2612 LOGIC
    //////////////////////////////////////////////////////////////*/

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public virtual {
        require(deadline >= block.timestamp, 'PERMIT_DEADLINE_EXPIRED');

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.
        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        '\x19\x01',
                        DOMAIN_SEPARATOR(),
                        keccak256(
                            abi.encode(
                                keccak256(
                                    'Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)'
                                ),
                                owner,
                                spender,
                                value,
                                ERC20Storage.layout().nonces[owner]++,
                                deadline
                            )
                        )
                    )
                ),
                v,
                r,
                s
            );

            require(recoveredAddress != address(0) && recoveredAddress == owner, 'INVALID_SIGNER');

            ERC20Storage.layout().allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return
            block.chainid == ERC20Storage.layout().INITIAL_CHAIN_ID
                ? ERC20Storage.layout().INITIAL_DOMAIN_SEPARATOR
                : computeDomainSeparator();
    }

    function computeDomainSeparator() internal view virtual returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                    keccak256(bytes(ERC20Storage.layout().name)),
                    keccak256('1'),
                    block.chainid,
                    address(this)
                )
            );
    }

    /*//////////////////////////////////////////////////////////////
                        INTERNAL MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal virtual {
        _beforeTokenTransfer(address(0), to, amount);
        ERC20Storage.layout().totalSupply += amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            ERC20Storage.layout().balanceOf[to] += amount;
        }

        emit Transfer(address(0), to, amount);
        _afterTokenTransfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual {
        _beforeTokenTransfer(from, address(0), amount);
        ERC20Storage.layout().balanceOf[from] -= amount;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            ERC20Storage.layout().totalSupply -= amount;
        }

        emit Transfer(from, address(0), amount);
        _afterTokenTransfer(from, address(0), amount);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

