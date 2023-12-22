pragma solidity ^0.8.0;

interface IDatabase {
    enum STATUS {
        NOTAUDITED,
        PENDING,
        PASSED,
        FAILED,
        REFUNDED
    }

    function HYACINTH_FEE() external view returns (uint256);

    function USDC() external view returns (address);

    function audits(uint256 auditId_) external view returns (address, address, STATUS, string memory, uint256, bool);

    function auditors(address auditor_) external view returns (uint256, uint256, uint256, uint256);

    function approvedAuditor(address auditor_) external view returns (bool isAuditor_);

    function hyacinthWallet() external view returns (address);

    function beingAudited() external;

    function mintPOD() external returns (uint256 id_, address developerWallet_);

    function addApprovedAuditor(address[] calldata auditors_) external;

    function removeApprovedAuditor(address[] calldata auditors_) external;

    function giveAuditorFeedback(uint256 auditId_, bool positive_) external;

    function refundBounty(uint256 auditId_) external;

    function submitResult(uint256 auditId_, STATUS result_, string memory description_) external;

    function rollOverExpired(uint256 auditId_) external;

    function levelsCompleted(address auditor_) external view returns (uint256[4] memory);

    function auditStatus(address contractAddress_) external view returns (STATUS status_);
}

