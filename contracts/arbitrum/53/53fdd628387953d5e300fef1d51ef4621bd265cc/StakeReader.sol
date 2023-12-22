//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.19;

import "./ERC721.sol";
import "./IStake.sol";

contract StakeReader {

    struct NFT {
      uint256 tokenID;
      string url;
    }

    constructor() {}

    function stakedNftCount(address _user, address _stake) public view returns (uint256) {
      IStake stakeContract = IStake(_stake);

      for (uint256 i = 0; i <= 2000; i++) {
        try stakeContract.stakelist(_user, i) {
        } catch {
          return i;
        }
      }

      return 0;
    }

    function stakedNftsOfOwner(address _user, address _stake, address _nft) public view returns (NFT[] memory, IStake.Stake[] memory, uint256[] memory) {
        uint256 count = stakedNftCount(_user, _stake);
        NFT[] memory nfts = new NFT[](count);
        IStake.Stake[] memory nftsInfo = new IStake.Stake[](count);
        IStake stakeContract = IStake(_stake);
        uint256[] memory rewards = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
          IStake.Stake memory staked = stakeContract.stakelist(_user, i);

          NFT memory nft;
          nft.tokenID =  uint256(staked.tokenId);
          nft.url = ERC721(_nft).tokenURI(staked.tokenId);

          nfts[i] = nft;
          nftsInfo[i] = staked;
          rewards[i] = stakeContract.calculateReward(staked.tokenId, staked.timeLevel, staked.lastClaimTime);
        }

        return (nfts, nftsInfo, rewards);
    }

    function calcAllReward(address _user, address _stake) public view returns (uint256) {
        uint256 count = stakedNftCount(_user, _stake);
        IStake stakeContract = IStake(_stake);
        uint256 totalReward = 0;

        for (uint256 i = 0; i < count; i++) {
          IStake.Stake memory staked = stakeContract.stakelist(_user, i);

          totalReward = totalReward + stakeContract.calculateReward(staked.tokenId, staked.timeLevel, staked.lastClaimTime);
        }

        return totalReward;
    }
}
