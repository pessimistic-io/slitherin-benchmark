//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./MerkleProofUpgradeable.sol";

import "./TLDMinterContracts.sol";

/************************************************************************************ 
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓████▓▓▓▓▓████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███▓▓▓██▓▓▓███▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓████▓▓▓▓███▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███▓▓▓████▓▓███▓▓▓▓▓▓▓▓▓▓▓▓▓████▓▓▓▓▓▓███▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███▓▓▓████▓▓████▓▓▓▓▓▓▓▓▓▓▓▓███▓▓▓▓▓▓▓███▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██▓▓█████▓▓███▓▓▓▓▓▓▓▓▓▓▓██▓▓▓▓██▓▓▓███▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓████▓█████▓▓███▓▓▓▓▓▓▓▓███▓▓▓████▓▓███▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███▓█████▓▓████▓▓▓▓▓▓███▓▓█████▓████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓████▓████▓▓▓███▓▓▓▓▓████▓█████▓████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███▓████▓▓▓▓█████████▓▓▓████▓████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████▓▓▓▓▓▓▓▓▓▌╬███████╬╣▓▓▓▓▓▓████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████▓▓▓▓▓▓▓▓▓╬╬╬╬╬╬╬╬╬╬╬╬╬╣╣▓▓▓███▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████▓▓█▓▓▓▓▓▓▓╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬▓██▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███████████████▓▓▓▓╣╬╬╬╬╬╬╬╬╬╬╬╬╬╬███▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓████████████████▓▓▓▓▓╬╬╬╬╬╬╬╬╬╬╬╬╬╬╬███▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓████████████████████▀▀████▓╬╬╬╬╬╬╬▓▀████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓████████████████▓▓██  ████╬╬║╝╝╝╝╣███▌▓██▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███████████████▓▓▓▓█████▓▓``       ╙╙╙╙╙╙█████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███████████████▓▓╬╬╬╬╬╬╩╙  «░░▓▓▄▄α   ╒▄α  └▀███▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓███████████▓▓╬╫╬╬╬╬╙      "ⁿ²████╬   ╟█▓▄▄, ▀███▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓█████████▓▓╬╬╬╠╬╝Γ           ≥≥▓▓╝ ≥≥╫████▌  ███▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████▓▓▓▓╬╬╬░╙                             ███▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████████▓╬╬╬╬░░««░      ██▌      ▒█⌐        ███▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓████████▓███████▓▓░░░░░░     █████,,,,▒█▄,,,,,  ▄███▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓▓▓▓██████▓▓▓▓▓▓▓▓▓███████▌▄▄░░░░░░░░╫█████████████▒Q▄███▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓█████████▓▓▓▓▓╬╬╣▓▓███████████▒░░░░░░░░░░░░░░░░░░█████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓▓▓██████▓▓▓▓▓▌╬╬╬╬╬╬╬╬▓███▓▓██████████████████████████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓████████▓▓▓╬╬╬╬╬╬╬╬╬▓▓▌╣▓╬╬▓▓▓▓▓▓▓▓▓▓▓▓███▓▓▓████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
    ▓▓▓▓▓▓▓▓▓██████▓▓▓▓▓╬╬╬╬╬╬╬╬▌███▌╝╬╬╬╬╬╣╣╣╣╣▓▓▓╬▓▓▓╬▓██████▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓

    HOIHAW
*************************************************************************************/

contract TLDMinter is Initializable, TLDMinterContracts {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        TLDMinterContracts.__TLDMinterContracts_init();
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyAdminOrOwner {
        merkleRoot = _merkleRoot;
    }

    function setMaxBatchSize(uint8 _maxBatchSize) external onlyAdminOrOwner {
        maxBatchSize = _maxBatchSize;
    }

    function airdrop(address _to, uint256 _amount)
        external
        onlyAdminOrOwner
        whenNotPaused
        contractsAreSet
    {
        uint256 _amountLeft = _amount;
        while (_amountLeft > 0) {
            uint256 _batchSize = _amountLeft > maxBatchSize
                ? maxBatchSize
                : _amountLeft;
            _amountLeft -= _batchSize;
            tld.mint(_to, _batchSize);
            emit TLDMint(_to, _batchSize);
        }
    }

    function mint(bytes32[] calldata _proof)
        external
        whenNotPaused
        onlyEOA
        contractsAreSet
    {
        require(
            !addressToHasClaimed[msg.sender],
            "TLDMinter: Donkeys already claimed, hoihaw!"
        );

        bytes32 _leaf = keccak256(abi.encodePacked(msg.sender));

        require(
            MerkleProofUpgradeable.verify(_proof, merkleRoot, _leaf),
            "TLDMinter: Proof invalid"
        );

        addressToHasClaimed[msg.sender] = true;

        tld.mint(msg.sender, 1);
        emit TLDMint(msg.sender, 1);
    }

    function hasClaimed(address _address) external onlyEOA contractsAreSet view returns (bool){
        return addressToHasClaimed[_address];
    }
}

