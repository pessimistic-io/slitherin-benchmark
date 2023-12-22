//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";
import "./StringsUpgradeable.sol";
import "./DonkeBoardMinterState.sol";

// CONTRACT THAT HANDLES THE STUFF RELATED TO $$$ AND SALES AND OWNERSHIP
abstract contract DonkeBoardMinterAdmin is
    Initializable,
    DonkeBoardMinterState
{
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using StringsUpgradeable for uint256;

    uint256 public price;

    // -------------------------------------------------------------
    //                       Initializer
    // -------------------------------------------------------------

    function __DonkeBoardMinterAdmin_init() internal initializer {
        price = 25;
        DonkeBoardMinterState.__DonkeBoardMinterState_init();
    }

    // -------------------------------------------------------------
    //               External Admin/Owner Functions
    // -------------------------------------------------------------

    /// @notice Change stored merkle root attached
    /// @dev Change to 0x0000000000000000000000000000000000000000000000000000000000000000 to remove whitelist.
    /// @param _merkleRoot New merkle root for whitelist verification or empty root for normal sale.
    function changeMerkleRoot(bytes32 _merkleRoot) external onlyAdminOrOwner {
        merkleRoot = _merkleRoot;
    }

    /// @notice Withdraw all Magic from contract.
    function withdrawMagic() external contractsAreSet onlyAdminOrOwner {
        uint256 contractBalance = magicToken.balanceOf(address(this));
        magicToken.transfer(treasuryAddress, contractBalance);
    }

    function setContracts(
        address _donkeBoard,
        address _magicToken,
        address _treasuryAddress
    ) external onlyAdminOrOwner {
        donkeBoard = IDonkeBoard(_donkeBoard);
        magicToken = IERC20Upgradeable(_magicToken);
        treasuryAddress = _treasuryAddress;
    }

    modifier contractsAreSet() {
        require(
            areContractsSet(),
            "DonkeBoardMinterAdmin: Contracts aren't set"
        );
        _;
    }

    function areContractsSet() public view returns (bool) {
        return
            address(donkeBoard) != address(0) &&
            address(magicToken) != address(0) &&
            address(treasuryAddress) != address(0);
    }
}

