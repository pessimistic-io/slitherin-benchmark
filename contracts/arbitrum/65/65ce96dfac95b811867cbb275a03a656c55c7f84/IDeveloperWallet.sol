pragma solidity ^0.8.0;

interface IDeveloperWallet {
    function payOutBounty(
        uint256 auditId_,
        address[] calldata collaborators_,
        uint256[] calldata percentsOfBounty_
    ) external returns (uint256 level_);

    function rollOverBounty(uint256 previous_, uint256 new_) external;

    function refundBounty(uint256 auditId_) external;

    function currentBountyLevel(uint256 auditId_) external view returns (uint256 level_, uint256 bounty_);

    function addToBounty(uint256 auditId_, uint256 amount_, bool transfer_, address token_) external;
}

