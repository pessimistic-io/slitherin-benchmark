// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;

import "./IERC20.sol";
import "./VoteImplementation.sol";

contract VoteImplementationArbitrum is VoteImplementation {

    function getVotePower(address account, uint256 lTokenId) public view returns (uint256 power) {
        address deri = 0x21E60EE73F17AC0A411ae5D690f908c3ED66Fe12;
        address lToken = 0xD849c2b7991060023e5D92b92c68f4077AE2C2Ba;
        address vaultDeri = 0xc8Eef19C657C46CbD9AB7cA45f2F00a74b4AC141;

        // balance in wallet
        power += IERC20(deri).balanceOf(account);

        // balance in V4 Gateway
        if (lTokenId != 0) {
            require(IDToken(lToken).ownerOf(lTokenId) == account, 'account not own lTokenId');
            power += IVault(vaultDeri).getBalance(lTokenId);
        }
    }

    function getVotePowers(address[] memory accounts, uint256[] memory lTokenIds) external view returns (uint256[] memory) {
        require(accounts.length == lTokenIds.length, 'accounts length not match lTokenIds length');
        uint256[] memory powers = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; i++) {
            powers[i] = getVotePower(accounts[i], lTokenIds[i]);
        }
        return powers;
    }

}

interface IDToken {
    function ownerOf(uint256) external view returns (address);
}

interface IVault {
    function getBalance(uint256 dTokenId) external view returns (uint256 balance);
}

