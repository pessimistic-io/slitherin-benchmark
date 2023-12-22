// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC1155SupplyUpgradeable} from "./ERC1155SupplyUpgradeable.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {StringsUpgradeable} from "./StringsUpgradeable.sol";
import {EnumerableSetUpgradeable} from "./EnumerableSetUpgradeable.sol";

contract SandGlassOfTime is OwnableUpgradeable, ERC1155SupplyUpgradeable {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;
    using StringsUpgradeable for uint;

    string public name;
    string public symbol;
    string private _baseUri;
    string public contractURI;

    EnumerableSetUpgradeable.AddressSet private _auth;

    event SetAuth(address addr, bool status);

    function __SandGlassOfTime_init(
        string memory name_,
        string memory symbol_,
        string memory baseUri
    ) external initializer {
        __Ownable_init_unchained();

        name = name_;
        symbol = symbol_;
        _baseUri = baseUri;
    }

    function mintOfficial(uint id, address[] calldata recipients, uint[] calldata amounts, uint amountPer) external onlyOwner {
        requireValidId(id);
        uint len = recipients.length;
        if (amountPer != 0) {
            for (uint i = 0; i < len; ++i) {
                _mint(recipients[i], id, amountPer, "");
            }
        } else {
            for (uint i = 0; i < len; ++i) {
                _mint(recipients[i], id, amounts[i], "");
            }
        }
    }

    function mintSingle(address recipient, uint id) external {
        require(_auth.contains(msg.sender), "unauthorized");
        requireValidId(id);
        _mint(recipient, id, 1, "");
    }

    function setAuth(address authAddr, bool added) external onlyOwner {
        added ? _auth.add(authAddr) : _auth.remove(authAddr);
    }

    function setBaseURI(string memory newBaseURI) external onlyOwner {
        _baseUri = newBaseURI;
    }

    function setContractURI(string memory newContractURI) external onlyOwner {
        contractURI = newContractURI;
    }

    function allAuth() external view returns (address[] memory){
        return _auth.values();
    }

    function requireValidId(uint id) private pure {
        require(id > 0 && id < 5, "invalid id");
    }

    function totalSupply() external view returns (uint total){
        for (uint i = 1; i < 5; ++i) {
            total += totalSupply(i);
        }
    }

    function getUnlockedUpperLimit(uint id) external pure returns (uint upperUnlockedLimit) {
        requireValidId(id);
        if (id == 1) {
            upperUnlockedLimit = 500e18;
        } else if (id == 2) {
            upperUnlockedLimit = 1000e18;
        } else if (id == 3) {
            upperUnlockedLimit = 1500e18;
        } else if (id == 4) {
            upperUnlockedLimit = 3000e18;
        }
    }

    function uri(uint id) public view override returns (string memory) {
        require(exists(id), "id not exist");
        return string(abi.encodePacked(_baseUri, id.toString()));
    }

    uint[44] private __gap;
}


