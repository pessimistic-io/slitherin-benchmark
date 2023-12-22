// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./OFTV2.sol";
import "./EnumerableSet.sol";
import "./Ownable.sol";

contract XMozToken is Ownable, OFTV2 {
    
    using EnumerableSet for EnumerableSet.AddressSet;
    address public multiSigAdmin;
    address public mozStaking;
    EnumerableSet.AddressSet private _transferWhitelist; // addresses allowed to send/receive xMOZ

    event SetTransferWhitelist(address account, bool add);

    constructor(
        address _layerZeroEndpoint, 
        address _multiSigAdmin,
        address _mozStaking,
        uint8 _sharedDecimals
    ) OFTV2("Mozaic escrowed token", "xMOZ", _sharedDecimals, _layerZeroEndpoint) {
        require(_mozStaking != address(0x0) || _multiSigAdmin != address(0x0), "Invalid addr");
        _transferWhitelist.add(address(this));
        mozStaking = _mozStaking;
        multiSigAdmin = _multiSigAdmin;
    }

    modifier onlyMultiSigAdmin() {
        require(msg.sender == multiSigAdmin, "Invalid caller");
        _;
    }

    modifier onlyStakingContract() {
        require(msg.sender == mozStaking, "Invalid caller");
        _;
    }
    /**
    * @dev Hook override to forbid transfers except from whitelisted addresses and minting
    */
    function _beforeTokenTransfer(address from, address to, uint256 /*amount*/) internal view override {
        require(from == address(0) || to == address(0) && msg.sender == mozStaking || from == owner() || isTransferWhitelisted(from), "transfer: not allowed");
    }

    /**
    * @dev returns length of transferWhitelist array
    */
    function transferWhitelistLength() external view returns (uint256) {
        return _transferWhitelist.length();
    }

    /**
    * @dev returns transferWhitelist array item's address for "index"
    */
    function transferWhitelist(uint256 index) external view returns (address) {
        return _transferWhitelist.at(index);
    }

    /**
    * @dev returns if "account" is allowed to send/receive xMOZ
    */
    function isTransferWhitelisted(address account) public view returns (bool) {
        return _transferWhitelist.contains(account);
    }

    /**
    * @dev Adds or removes addresses from the transferWhitelist
    */
    function updateTransferWhitelist(address account, bool add) external onlyMultiSigAdmin {
        require(account != address(this), "updateTransferWhitelist: Cannot remove xMoz from whitelist");

        if(add) _transferWhitelist.add(account);
        else _transferWhitelist.remove(account);

        emit SetTransferWhitelist(account, add);
    }

    function mint(uint256 _amount, address _to) external onlyStakingContract {
        _mint(_to, _amount);
    }

    function burn(uint256 _amount, address _from) external onlyStakingContract {
        _burn(_from, _amount);
    }
}
