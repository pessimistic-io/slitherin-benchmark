// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.11;

import "./OwnableUpgradeable.sol";
import "./AddressUpgradeable.sol";

import "./IZeus.sol";




abstract contract ZeusImplementationPointerUpgradeable is OwnableUpgradeable {
    IZeus internal zeus;

    event UpdateZeus(
        address indexed oldImplementation,
        address indexed newImplementation
    );

    modifier onlyZeus() {
        require(
            address(zeus) != address(0),
            "Implementations: zeus is not set"
        );
        address sender = _msgSender();
        require(
            sender == address(zeus),
            "Implementations: Not zeus"
        );
        _;
    }

    function getZeusImplementation() public view returns (address) {
        return address(zeus);
    }

    function changeZeusImplementation(address newImplementation)
        public
        virtual
        onlyOwner
    {
        address oldImplementation = address(zeus);
        require(
            AddressUpgradeable.isContract(newImplementation) ||
                newImplementation == address(0),
            "zeus: You can only set 0x0 or a contract address as a new implementation"
        );
        zeus = IZeus(newImplementation);
        emit UpdateZeus(oldImplementation, newImplementation);
    }

    uint256[49] private __gap;
}
