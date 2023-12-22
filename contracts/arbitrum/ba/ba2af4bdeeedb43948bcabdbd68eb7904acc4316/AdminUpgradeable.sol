// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

abstract contract AdminUpgradeable {
    address public admin;
    address public adminCandidate;

    function _initializeAdmin(address _admin) internal {
        require(admin == address(0), "admin already set");

        admin = _admin;
    }

    function candidateConfirm() external {
        require(msg.sender == adminCandidate, "not Candidate");
        emit AdminChanged(admin, adminCandidate);

        admin = adminCandidate;
        adminCandidate = address(0);
    }

    function setAdminCandidate(address _candidate) external onlyAdmin {
        adminCandidate = _candidate;
        emit Candidate(_candidate);
    }

    modifier onlyAdmin {
        require(msg.sender == admin, "not admin");
        _;
    }

    event Candidate(address indexed newAdmin);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
}
