// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Drop.sol";
import "./PermissionsEnumerable.sol";

contract CDAOToken is ERC20Drop, PermissionsEnumerable {
    bytes32 private transferRole;
    uint256 public maxTotalSupply;
    uint8 private scale;

    mapping(address => bool) private exchangeLimit;
    mapping(address => uint256) private totalSupplyClaimed;

    event MaxTotalSupplyUpdated(uint256 maxTotalSupply);

    constructor(
        address _defaultAdmin,
        string memory _name,
        string memory _symbol,
        address _primarySaleRecipient,
        uint8 _scale,
        uint256 _maxTotalSupply
    ) ERC20Drop(_defaultAdmin, _name, _symbol, _primarySaleRecipient) {
        bytes32 _transferRole = keccak256("TRANSFER_ROLE");

        _setupRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setupRole(_transferRole, _defaultAdmin);
        _setupRole(_transferRole, address(0));

        transferRole = _transferRole;
        _scale = _scale / 10;
        scale = (_scale <= 10) ? _scale : 5;
        maxTotalSupply = _maxTotalSupply;
    }

    function setMaxTotalSupply(uint256 _maxTotalSupply) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxTotalSupply = _maxTotalSupply;
        emit MaxTotalSupplyUpdated(_maxTotalSupply);
    }

    function _beforeClaim(address, uint256 _quantity, address, uint256, AllowlistProof calldata, bytes memory)
        internal
        view
        override
    {
        uint256 _maxTotalSupply = maxTotalSupply;
        require(_maxTotalSupply == 0 || totalSupply() + _quantity <= _maxTotalSupply, "exceed max total supply.");
    }

    function _afterClaim(address _receiver, uint256 _quantity, address, uint256, AllowlistProof calldata, bytes memory)
        internal
        override
    {
        totalSupplyClaimed[_receiver] += _quantity;
    }

    function _canSetClaimConditions() internal view override returns (bool) {
        return hasRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        super._beforeTokenTransfer(from, to, amount);

        if (!hasRole(transferRole, address(0)) && from != address(0) && to != address(0)) {
            require(hasRole(transferRole, from) || hasRole(transferRole, to), "transfers restricted.");
        }
        if (exchangeLimit[from]) {
            require(
                (balanceOf(from) - amount) >= maxTransferByWallet(from),
                "You are limited to the amount you can transfer"
            );
        }
    }

    function addExchangeLimitLists(address[] calldata _addresses) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_addresses.length > 0, "Empty address array");

        for (uint256 i = 0; i < _addresses.length; i++) {
            address _address = _addresses[i];
            require(_address != address(0), "Invalid address");
            exchangeLimit[_address] = true;
        }
    }

    function removeExchangeLimitLists(address[] calldata _addresses) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_addresses.length > 0, "Empty address array");

        for (uint256 i = 0; i < _addresses.length; i++) {
            address _address = _addresses[i];
            require(_address != address(0), "Invalid address");
            exchangeLimit[_address] = false;
        }
    }

    function checkExchangeLimitByWallet(address _address) public view returns (bool) {
        return exchangeLimit[_address];
    }

    function maxTransferByWallet(address _address) public view returns (uint256) {
        uint256 _supplyclaimed = totalSupplyClaimed[_address];
        if (exchangeLimit[_address]) {
            return _supplyclaimed - ((_supplyclaimed / 10) * scale);
        }

        return _supplyclaimed;
    }

    function setScale(uint8 _number) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_number >= 10 && _number <= 100, "Number Between (10,100)");
        require(_number % 10 == 0, "Number must be divisible by 10");

        scale = _number / 10;
    }

    function getScale() public view returns (uint256) {
        return scale * 10;
    }

    function getTotalSupplyClaimedbyWallet(address _address) public view returns (uint256) {
        return totalSupplyClaimed[_address];
    }
}

