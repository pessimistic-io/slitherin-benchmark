//SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.0;

import "./ERC20PresetMinterPauser.sol";

import "./draft-ERC20Permit.sol";

interface IArbToken {
    /**
     * @notice should increase token supply by amount, and should (probably) only be callable by the L1 bridge.
     */
    function bridgeMint(address account, uint256 amount) external;

    /**
     * @notice should decrease token supply by amount, and should (probably) only be callable by the L1 bridge.
     */
    function bridgeBurn(address account, uint256 amount) external;

    /**
     * @return address of layer 1 token
     */
    function l1Address() external view returns (address);
}

contract Cudl is IArbToken, ERC20PresetMinterPauser, ERC20Permit {
    address public l2Gateway;
    address public override l1Address;

    modifier onlyGateway() {
        require(msg.sender == l2Gateway, "ONLY_GATEWAY");
        _;
    }

    constructor(address l2Gateway_, address l1Counterpart_)
        ERC20PresetMinterPauser("CUDL", "CUDL")
        ERC20Permit("CUDL")
    {
        require(l2Gateway_ != address(0), "INVALID_GATEWAY");
        require(l2Gateway == address(0), "ALREADY_INIT");
        l2Gateway = l2Gateway_;
        l1Address = l1Counterpart_;
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20, ERC20PresetMinterPauser) {
        super._beforeTokenTransfer(from, to, amount);
    }

    function bridgeMint(address account, uint256 amount)
        external
        virtual
        override
        onlyGateway
    {
        _mint(account, amount);
    }

    /**
     * @notice Burn tokens on L2.
     * @dev only the token bridge can call this
     * @param account owner of tokens
     * @param amount amount of tokens burnt
     */
    function bridgeBurn(address account, uint256 amount)
        external
        virtual
        override
        onlyGateway
    {
        _burn(account, amount);
    }
}

