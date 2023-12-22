pragma solidity ^0.8.0;

interface IDatabase {
    enum STATUS {
        NOTAUDITED,
        PENDING,
        PASSED,
        FAILED
    }

    function beingAudited(address previous_) external;
    function HYACINTH_FEE() external view returns (uint256);
    function approvedAuditor(address auditor_) external view returns (bool isAuditor_);
    function hyacinthWallet() external view returns (address);
    function USDC() external view returns (address);
    function levelsCompleted(address auditor_) external view returns (uint256[4] memory);
    function mintedLevel(address auditor_) external view returns (uint256 baseLevel_);
    function audits(address contract_) external view returns (address, address, STATUS, string memory, bool);
    function auditors(address auditor_) external view returns (uint256, uint256, uint256, uint256);
}
