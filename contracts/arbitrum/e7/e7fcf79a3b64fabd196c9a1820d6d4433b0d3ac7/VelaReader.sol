// SPDX-License-Identifier: MIT

pragma solidity 0.8.9;

import "./AddressUpgradeable.sol";
import "./Initializable.sol";
import "./IVela.sol";

contract VelaReader is Initializable {
    IVELA private vela;
    IVELA private esVela;

    function initialize(IVELA _vela, IVELA _esVela) public initializer {
        require(AddressUpgradeable.isContract(address(_esVela)), "esVela invalid");
        require(AddressUpgradeable.isContract(address(_vela)), "vela invalid");
        esVela = _esVela;
        vela = _vela;
    }

    function getVelaInfo(address[] memory subAddresses) external view returns (uint256, uint256, uint256) {
        uint256 velaTotalSupply = vela.totalSupply();
        uint256 velaMaxSupply = vela.maxSupply();
        uint256 esVelaTotalSupply = esVela.totalSupply();
        uint256 totalToSubtract = 0;
        for (uint256 i = 0; i < subAddresses.length; i++) {
            totalToSubtract += vela.balanceOf(subAddresses[i]);
        }
        uint256 circulatingSupply = velaTotalSupply - esVelaTotalSupply - totalToSubtract;
        return (velaMaxSupply / 2, velaTotalSupply - esVelaTotalSupply, circulatingSupply);
    }
}

