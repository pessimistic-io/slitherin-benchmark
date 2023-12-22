/**
 * SPDX-License-Identifier: Proprietary
 * 
 * Strateg Protocol contract
 * PROPRIETARY SOFTWARE AND LICENSE. 
 * This contract is the valuable and proprietary property of Strateg Development Association. 
 * Strateg Development Association shall retain exclusive title to this property, and all modifications, 
 * implementations, derivative works, upgrades, productizations and subsequent releases. 
 * To the extent that developers in any way contributes to the further development of Strateg protocol contracts, 
 * developers hereby irrevocably assign and/or agrees to assign all rights in any such contributions or further developments to Strateg Development Association. 
 * Without limitation, Strateg Development Association acknowledges and agrees that all patent rights, 
 * copyrights in and to the Strateg protocol contracts shall remain the exclusive property of Strateg Development Association at all times.
 * 
 * DEVELOPERS SHALL NOT, IN WHOLE OR IN PART, AT ANY TIME: 
 * (i) SELL, ASSIGN, LEASE, DISTRIBUTE, OR OTHER WISE TRANSFER THE STRATEG PROTOCOL CONTRACTS TO ANY THIRD PARTY; 
 * (ii) COPY OR REPRODUCE THE STRATEG PROTOCOL CONTRACTS IN ANY MANNER;
 */
pragma solidity ^0.8.15;

import "./Ownable.sol";
import "./Strings.sol";

contract StrategStepRegistry is Ownable {

    uint256 public stepsLength;
    mapping(uint256 => address) public steps; 

    event NewStep(uint256 indexed step, address addr);

    constructor(address[] memory _initialSteps) {
        for (uint i = 0; i < _initialSteps.length; i++) {
            steps[i] = _initialSteps[i];
        }

        stepsLength = _initialSteps.length;
    }

    function addSteps(address[] memory _steps) external onlyOwner {
        for (uint i = 0; i < _steps.length; i++) {
            steps[stepsLength + i] = _steps[i];
            emit NewStep(stepsLength + i, _steps[i]);
        }

        stepsLength = stepsLength + _steps.length;
    }

    function getSteps(uint256[] memory _steps) external view returns (address[] memory) {
        address[] memory addresses = new address[](_steps.length);

        for (uint i = 0; i < _steps.length; i++) {
            addresses[i] = steps[_steps[i]];
            if(addresses[i] == address(0)) {
                revert(string.concat(Strings.toString(_steps[i]), " step unknown"));
            }
        }

        return addresses;
    }
}

