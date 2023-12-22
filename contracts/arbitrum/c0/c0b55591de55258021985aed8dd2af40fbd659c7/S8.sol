// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Challenge} from "./Challenge.sol";

contract S8 is Challenge {
    mapping(address => string) private s_auditUri;
    mapping(address => string) private s_addressToUsername;

    constructor(address registry) Challenge(registry) {}

    /*
     * CALL THIS FUNCTION!
     * 
     * All you have to do here, is upload a URI with either:
     *   - A link to your Vault Guardians Security Review
     *   - A link to your participation in a CodeHawks competitive audit or first flight
     * 
     * Vault Guardians Example: https://github.com/Cyfrin/8-vault-guardians-audit/blob/main/audit-data/report.pdf
     * (Bonus points for IPFS or Arweave links!)
     * CodeHawks Example: https://www.codehawks.com/report/clomptuvr0001ie09bzfp4nqw
     * 
     * Careful: You can only call this function once on this address!
     * 
     * @param auditOrCodeHawksUri - The URI to your Vault Guardians security review or CodeHawks report
     * @param username - Your CodeHawks username 
     * @param twitterHandle - Your twitter handle - can be blank
     */
    function solveChallenge(string memory auditOrCodeHawksUri, string memory username, string memory twitterHandle)
        external
    {
        s_auditUri[msg.sender] = auditOrCodeHawksUri;
        s_addressToUsername[msg.sender] = username;
        _updateAndRewardSolver(twitterHandle);
    }

    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    /////////////////// The following are functions needed for the NFT, feel free to ignore. ///////////////////
    ////////////////////////////////////////////////////////////////////////////////////////////////////////////
    function attribute() external pure override returns (string memory) {
        return "MMMEEEVVVVVVERRINNGGG";
    }

    function description() external pure override returns (string memory) {
        return "Section 8: MEV/Vault Guardians";
    }

    function extraDescription(address user) external view override returns (string memory) {
        string memory auditUri = s_auditUri[user];
        string memory username = s_addressToUsername[user];
        return string.concat("\n\nAudit URI: ", auditUri, "\nUsername: ", username);
    }

    function specialImage() external pure returns (string memory) {
        // This is b8.png
        return "ipfs://QmXt9s7EWGK3AVmLDRbw6pRJJ5JdHg4qJZzk85jqj2NmQU";
    }
}

