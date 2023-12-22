//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./MerkleProofUpgradeable.sol";

import "./DonkeBoardMinterAdmin.sol";

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

contract DonkeBoardMinter is Initializable, DonkeBoardMinterAdmin {
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    function initialize() external initializer {
        DonkeBoardMinterAdmin.__DonkeBoardMinterAdmin_init();
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyAdminOrOwner {
        merkleRoot = _merkleRoot;
    }

    function setMaxBatchSize(uint8 _maxBatchSize) external onlyAdminOrOwner {
        maxBatchSize = _maxBatchSize;
    }

    function airdrop(
        address _to,
        uint256 _amount
    ) external onlyAdminOrOwner whenNotPaused contractsAreSet {
        uint256 _amountLeft = _amount;
        while (_amountLeft > 0) {
            uint256 _batchSize = _amountLeft > maxBatchSize
                ? maxBatchSize
                : _amountLeft;
            _amountLeft -= _batchSize;
            donkeBoard.mint(_to, _batchSize);
            emit DonkeBoardMint(_to, _batchSize);
        }
    }

    /// @dev Check balance of magic for user.
    function _checkMagicBalance(
        address _userAddress,
        uint256 _amount
    ) internal view {
        uint256 bal = magicToken.balanceOf(_userAddress);
        if (bal < _amount) revert InsufficientBalance(bal, _amount);
    }

    function mint(
        uint256 _amount
    ) external whenNotPaused onlyEOA contractsAreSet {
        require(
            donkeBoard.numTokenCount() >= _amount,
            "Amount is greater than available token"
        );

        uint256 magicCost = price * 10 ** 18 * _amount;
        _checkMagicBalance(msg.sender, magicCost);
        magicToken.transferFrom(msg.sender, address(this), magicCost);
        donkeBoard.mint(msg.sender, _amount);
        emit DonkeBoardMint(msg.sender, _amount);
    }

    /// @dev _amount is the full amount the user is allowlisted for. T
    /// the function will claim whatever is unclaimed
    function claim(
        bytes32[] calldata _proof,
        uint256 _amount
    ) external whenNotPaused onlyEOA contractsAreSet {
        bytes32 _leaf = keccak256(abi.encodePacked(msg.sender, _amount));
        require(
            MerkleProofUpgradeable.verify(_proof, merkleRoot, _leaf),
            "DonkeBoardMinter: Proof invalid"
        );

        uint256 amountToClaim = _amount - addressToHasClaimedAmount[msg.sender];

        require(
            amountToClaim >= 1,
            "DonkeBoardMinter: DonkeBoard already claimed, hoihaw!"
        );

        require(
            donkeBoard.numTokenCount() >= amountToClaim,
            "Amount is greater than available token"
        );

        addressToHasClaimedAmount[msg.sender] += amountToClaim;

        donkeBoard.mint(msg.sender, amountToClaim);
        emit DonkeBoardMint(msg.sender, amountToClaim);
    }

    function hasClaimedAmount(
        address _address
    ) external view onlyEOA contractsAreSet returns (uint256) {
        return addressToHasClaimedAmount[_address];
    }
}

