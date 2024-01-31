//SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "./IERC20.sol";
import "./IERC721.sol";
import "./ISpecialPool.sol";
import "./SpecialValidatePoolLibrary.sol";
interface IIDO{
    function holdingNFTs(uint256) external view returns(address);
    function tiersForNFTs(uint256) external view returns(uint256);
    function tiersForAccounts(address) external view returns(uint256);
    function holdingToken() external view returns(address);
    function holdingStakedToken() external view returns(address);
    function holdingTokenAmount(uint256) external view returns(uint256);
    function holdingStakedTokenAmount(uint256) external view returns(uint256);
    function getAccountsAndNftsForTier() external view returns(address[] memory accounts, address[] memory nfts, uint256[] memory tiers);
}
library SpecialDepositPoolLibrary {

    function whitelistCheckForNFTAndAccount(
        uint256 isTier,
        bool isTieredWhitelist,
        uint256 startDateTime,
        IIDO ido
    ) external view returns(bool) {
        if(isTier<ido.tiersForAccounts(msg.sender) || (isTieredWhitelist && isTier==4 && isTier<=ido.tiersForAccounts(msg.sender) &&
        block.timestamp >= startDateTime + 10 minutes)){
            return true;
        }
        (, address[] memory nfts, uint256[] memory tiers)=ido.getAccountsAndNftsForTier();
        for(uint256 i=0;i<nfts.length;i++){
            if(IERC721(nfts[i]).balanceOf(msg.sender)>0 && (tiers[i]>isTier || (isTieredWhitelist &&
                isTier==4 && tiers[i]>=isTier &&
                block.timestamp >= startDateTime + 10 minutes
            ))){
                return true;
            }
        }
        return false;
    }

    function whitelistCheckForTokenHolders(
        address holdingToken,
        address holdingStakedToken,
        uint256[6] calldata amounts,
        bool isTieredWhitelist
    ) external view returns(bool) {
        if((holdingToken != address(0) &&
                        IERC20(holdingToken).balanceOf(msg.sender) >= amounts[0]) ||
                (holdingStakedToken != address(0) &&
                IERC20(holdingStakedToken).balanceOf(msg.sender) >= amounts[1])
        )
            return true;            
        else{
            if(isTieredWhitelist && amounts[4]==4 && block.timestamp >= amounts[5] + 10 minutes &&
                (
                    (holdingToken != address(0) &&
                            IERC20(holdingToken).balanceOf(msg.sender) >= amounts[2]) ||
                    (holdingStakedToken != address(0) &&
                    IERC20(holdingStakedToken).balanceOf(msg.sender) >= amounts[3])
            ))
                return true;
            else
                return false;
        }
        
    }

    function whitelistCheck(
        bool isTieredWhitelist,
        uint256 startDateTime,
        mapping(address => bool) storage whitelistedAddressesMap,
        mapping(address => bool) storage whitelistedAddressesMapForTiered
    ) external view {
        if (isTieredWhitelist) {
            require(
                    (block.timestamp >=
                        startDateTime + 10 minutes &&
                        (whitelistedAddressesMap[msg.sender] ||
                            whitelistedAddressesMapForTiered[msg.sender])) ||
                    whitelistedAddressesMapForTiered[msg.sender],
                "Not!"
            );
        } else
            require(
                    whitelistedAddressesMap[msg.sender],
                "Not!"
            );
    }

    function depositPool(
        address[2] calldata addresses,
        mapping(address => uint256) storage _weiRaised,
        ISpecialPool.PoolModel storage poolInformation,
        mapping(address => uint256) storage collaborations,
        mapping(address => address[]) storage participantsAddress,
        uint256 amounts
    ) external {
        SpecialValidatePoolLibrary._poolIsOngoing(poolInformation);
        require(
            (addresses[1] != address(0) && amounts > 0) || msg.value > 0,
            "No WEI found!"
        );

        SpecialValidatePoolLibrary._minAllocationNotPassed(
            poolInformation.minAllocationPerUser,
            _weiRaised[addresses[0]],
            poolInformation.hardCap,
            collaborations[msg.sender],
            addresses[1],
            amounts
        );
        SpecialValidatePoolLibrary._maxAllocationNotPassed(
            poolInformation.maxAllocationPerUser,
            collaborations[msg.sender],
            addresses[1],
            amounts
        );
        SpecialValidatePoolLibrary._hardCapNotPassed(
            poolInformation.hardCap,
            _weiRaised[addresses[0]],
            addresses[1],
            amounts
        );
        if (collaborations[msg.sender] <= 0)
            participantsAddress[addresses[0]].push(msg.sender);
        if (addresses[1] == address(0)) {
            _weiRaised[addresses[0]] = _weiRaised[addresses[0]] + msg.value;
            collaborations[msg.sender] = collaborations[msg.sender] + msg.value;
            (bool sent, ) = payable(addresses[0]).call{value: msg.value}("");
            require(sent, "Failed to send Ether");
        } else {
            _weiRaised[addresses[0]] = _weiRaised[addresses[0]] + amounts;
            collaborations[msg.sender] = collaborations[msg.sender] + amounts;
            IERC20 _token = IERC20(addresses[1]);
            _token.transferFrom(msg.sender, addresses[0], amounts);
        }
    }
}

