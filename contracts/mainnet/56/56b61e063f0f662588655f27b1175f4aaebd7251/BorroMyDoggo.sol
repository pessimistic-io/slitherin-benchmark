// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./BitMaps.sol";
import "./ReentrancyGuard.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./IBAYCSewerPassClaim.sol";
import "./IDelegationRegistry.sol";

contract BorroMyDoggo is IERC721Receiver, ReentrancyGuard {
    using BitMaps for BitMaps.BitMap;

    address constant public SEWER_PASS = 0x764AeebcF425d56800eF2c84F2578689415a2DAa;
    address constant public SEWER_PASS_CLAIM = 0xBA5a9E9CBCE12c70224446C24C111132BECf9F1d;
    address constant public BAYC = 0xBC4CA0EdA7647A8aB7C2061c2E118A18a936f13D;
    address constant public MAYC = 0x60E4d786628Fea6478F785A6d7e704777c86a7c6;
    address constant public BAKC = 0xba30E5F9Bb24caa003E9f2f0497Ad287FDF95623;
    address constant public FOOBAR = 0xe5ee2B9d5320f2D1492e16567F36b578372B3d9F;
    address constant public THOMAS = 0x3e6a203ab73C4B35Be1F65461D88Fb21DE26446e;
    uint64 constant public LENDER_FEE = 90;
    IDelegationRegistry delegateCash = IDelegationRegistry(0x00000000000076A84feF008CDAbe6409d2FE638B);

    BitMaps.BitMap private doggoLoaned;
    mapping(uint256 => uint256) public borroCost;
    address private currentMinter;

    /** borroDoggos allows bayc/mayc holder to mint tier 4/tier 2 sewer pass
        apes must be delegated to this contract address by ape owner using delegate.cash
        using doggo delegated and loaned by a doggo holder
        payment must be greater than or equal to sum of all doggos used and can be calculated with calculateBorroCost
        sewer passes will be minted and transfered to the account that calls this function
        minter must be direct owner or delegate for the BAYC/MAYC tokens supplied
        BAYC or MAYC can be supplied as empty arrays but total apes must equal total doggos
        90% of borro fees go to doggo owner, 5% to 0xfoobar for delegate.cash and 5% to 0xth0mas
    */
    function borroDoggos(uint256[] calldata baycIds, uint256[] calldata maycIds, uint256[] calldata doggoIds) external payable nonReentrant {
        require((baycIds.length + maycIds.length) == doggoIds.length, "APE/DOGGO COUNT MISMATCH");
        uint256 totalBorroCost = this.calculateBorroCost(doggoIds);
        require(msg.value >= totalBorroCost, "INSUFFICIENT PAYMENT");
        uint256 doggoIndex = 0;
        currentMinter = msg.sender;
        address apeOwner;
        for(uint256 i = 0;i < baycIds.length;i++) {
            apeOwner = IERC721(BAYC).ownerOf(baycIds[i]);
            require(apeOwner == msg.sender ||
                delegateCash.checkDelegateForToken(msg.sender, apeOwner, BAYC, baycIds[i]), "NOT APE OWNER OR DELEGATE");
            IBAYCSewerPassClaim(SEWER_PASS_CLAIM).claimBaycBakc(baycIds[i], doggoIds[doggoIndex]);
            payDoggoOwner(doggoIds[doggoIndex]);
            doggoIndex++;
        }
        for(uint256 i = 0;i < maycIds.length;i++) {
            apeOwner = IERC721(MAYC).ownerOf(maycIds[i]);
            require(apeOwner == msg.sender ||
                delegateCash.checkDelegateForToken(msg.sender, apeOwner, MAYC, maycIds[i]), "NOT APE OWNER OR DELEGATE");
            IBAYCSewerPassClaim(SEWER_PASS_CLAIM).claimMaycBakc(maycIds[i], doggoIds[doggoIndex]);
            payDoggoOwner(doggoIds[doggoIndex]);
            doggoIndex++;
        }
        currentMinter = address(0);
    }

    /** friendly utility function for ape holders to bulk mint sewer passes
        apes & doggos must be delegated to this contract address by owner using delegate.cash
        doggos used for tier 4 sewer passes first, when doggo count is exceeded tier 3 passes get minted
        if doggos are left after bayc sewer passes, doggos used to mint tier 2 sewer passes
        if maycs are left after doggo count is exceeded, tier 1 passes are minted
        donations appreciated but not required to use
    */
    function bulkMintSewerPass(uint256[] calldata baycIds, uint256[] calldata maycIds, uint256[] calldata doggoIds) external payable nonReentrant {
        uint256 doggoIndex = 0;
        currentMinter = msg.sender;
        address apeOwner;
        address doggoOwner;
        for(uint256 baycIndex = 0;baycIndex < baycIds.length;baycIndex++) {
            apeOwner = IERC721(BAYC).ownerOf(baycIds[baycIndex]);
            require(apeOwner == msg.sender ||
                delegateCash.checkDelegateForToken(msg.sender, apeOwner, BAYC, baycIds[baycIndex]), "NOT APE OWNER OR DELEGATE");
            if(doggoIndex >= doggoIds.length) {
                IBAYCSewerPassClaim(SEWER_PASS_CLAIM).claimBayc(baycIds[baycIndex]);
            } else {
                doggoOwner = IERC721(BAKC).ownerOf(doggoIds[doggoIndex]);
                require(doggoOwner == msg.sender ||
                    delegateCash.checkDelegateForToken(msg.sender, doggoOwner, BAKC, doggoIds[doggoIndex]), "NOT DOGGO OWNER OR DELEGATE");
                IBAYCSewerPassClaim(SEWER_PASS_CLAIM).claimBaycBakc(baycIds[baycIndex], doggoIds[doggoIndex]);
                doggoIndex++;
            }
        }
        for(uint256 maycIndex = 0;maycIndex < maycIds.length;maycIndex++) {
            apeOwner = IERC721(MAYC).ownerOf(maycIds[maycIndex]);
            require(apeOwner == msg.sender ||
                delegateCash.checkDelegateForToken(msg.sender, apeOwner, MAYC, maycIds[maycIndex]), "NOT APE OWNER OR DELEGATE");
            if(doggoIndex >= doggoIds.length) {
                IBAYCSewerPassClaim(SEWER_PASS_CLAIM).claimMayc(maycIds[maycIndex]);
            } else {
                doggoOwner = IERC721(BAKC).ownerOf(doggoIds[doggoIndex]);
                require(doggoOwner == msg.sender ||
                    delegateCash.checkDelegateForToken(msg.sender, doggoOwner, BAKC, doggoIds[doggoIndex]), "NOT DOGGO OWNER OR DELEGATE");
                IBAYCSewerPassClaim(SEWER_PASS_CLAIM).claimMaycBakc(maycIds[maycIndex], doggoIds[doggoIndex]);
                doggoIndex++;
            }
        }
        currentMinter = address(0);
    }

    /** calculate and send payment for use of doggo in minting sewer pass, cleans up state
    */
    function payDoggoOwner(uint256 doggoId) internal {
        address doggoOwner = IERC721(BAKC).ownerOf(doggoId);
        uint256 payment = borroCost[doggoId] * LENDER_FEE / 100;
        (bool sent, ) = payable(doggoOwner).call{value: payment}("");
        require(sent);
        borroCost[doggoId] = 0;
        doggoLoaned.unset(doggoId);
    }

    /** withdraw fees for 0xfoobar and 0xth0mas
    */
    function withdraw() external {
        uint256 feesCollected = address(this).balance;
        uint256 foobarShare = feesCollected / 2;
        (bool fbSent, ) = payable(FOOBAR).call{value: foobarShare}("");
        require(fbSent);
        (bool tSent, ) = payable(THOMAS).call{value: (feesCollected -foobarShare)}("");
        require(tSent);
    }

    /** loan doggos for bayc/mayc to mint higher tier sewer passes
        doggos must be delegated to this contract address by doggo owner using delegate.cash
        doggoIds = array of doggos to loan out, must be direct owner or delegate to call
        costToBorro = payment to be received when your doggo is used to mint a sewer pass, cost is in WEI
        payment will be sent to doggo owner wallet
        can be called again to adjust costToBorro
    */
    function loanDoggos(uint256[] calldata doggoIds, uint256 costToBorro) external {
        address doggoOwner;
        for(uint256 doggoIndex = 0;doggoIndex < doggoIds.length;doggoIndex++) {
            doggoOwner = IERC721(BAKC).ownerOf(doggoIds[doggoIndex]);
            require(doggoOwner == msg.sender ||
                delegateCash.checkDelegateForToken(msg.sender, doggoOwner, BAKC, doggoIds[doggoIndex]), "NOT DOGGO OWNER OR DELEGATE");
            doggoLoaned.set(doggoIds[doggoIndex]);
            borroCost[doggoIds[doggoIndex]] = costToBorro;
        }
    }

    /** takes doggo off loan, you can also revoke delegation to this contract with delegate.cash for same effect
    */
    function unloanDoggos(uint256[] calldata doggoIds) external {
        address doggoOwner;
        for(uint256 doggoIndex = 0;doggoIndex < doggoIds.length;doggoIndex++) {
            doggoOwner = IERC721(BAKC).ownerOf(doggoIds[doggoIndex]);
            require(doggoOwner == msg.sender ||
                delegateCash.checkDelegateForToken(msg.sender, doggoOwner, BAKC, doggoIds[doggoIndex]), "NOT DOGGO OWNER OR DELEGATE");
            doggoLoaned.unset(doggoIds[doggoIndex]);
            borroCost[doggoIds[doggoIndex]] = 0;
        }
    }

    struct DoggoLoaned {
        uint64 doggoId;
        uint64 borroCost;
    }

    /** utility function to return list of available doggos for sewer pass minting and cost to borro for each doggo
        find cheapest doggo ids to borrow and supply array to calculateBorroCost for total cost
    */
    function availableDoggos() external view returns(DoggoLoaned[] memory) {
        uint256 doggosAvailable = 0;
        address doggoOwner;
        for(uint256 doggoIndex = 0;doggoIndex < 10000;doggoIndex++) {
            try IERC721(BAKC).ownerOf(doggoIndex) returns (address result) { doggoOwner = result; } catch { doggoOwner = address(0); }
            if(doggoLoaned.get(doggoIndex) && 
              delegateCash.checkDelegateForToken(address(this), doggoOwner, BAKC, doggoIndex) &&
              !IBAYCSewerPassClaim(SEWER_PASS_CLAIM).bakcClaimed(doggoIndex)) {
                doggosAvailable++;
            }
        }

        DoggoLoaned[] memory loans = new DoggoLoaned[](doggosAvailable);
        uint256 currentIndex = 0;
        for(uint256 doggoIndex = 0;doggoIndex < 10000;doggoIndex++) {
            try IERC721(BAKC).ownerOf(doggoIndex) returns (address result) { doggoOwner = result; } catch { doggoOwner = address(0); }
            if(doggoLoaned.get(doggoIndex) && 
              delegateCash.checkDelegateForToken(address(this), doggoOwner, BAKC, doggoIndex) &&
              !IBAYCSewerPassClaim(SEWER_PASS_CLAIM).bakcClaimed(doggoIndex)) {
                  DoggoLoaned memory dl;
                  dl.doggoId = uint64(doggoIndex);
                  dl.borroCost = uint64(borroCost[doggoIndex]);
                loans[currentIndex] = dl;
                currentIndex++;
                if(currentIndex >= doggosAvailable) { break; }
            }
        }
        return loans;
    }

    /** calculates total cost of doggo borrowing
    */
    function calculateBorroCost(uint256[] calldata doggoIds) external view returns(uint256 totalBorroCost) {
        for(uint256 i = 0;i < doggoIds.length;i++) {
            require(doggoLoaned.get(doggoIds[i]), "DOGGO NOT LOANED");
            totalBorroCost += borroCost[doggoIds[i]];
        }
    }

    /** receives sewer pass from sewer pass mint function, transfers to current minter
    */
    function onERC721Received(address operator, address, uint256 tokenId, bytes calldata) external returns (bytes4) {
        require(operator == SEWER_PASS_CLAIM);
        require(currentMinter != address(0));
        IERC721(SEWER_PASS).safeTransferFrom(address(this), currentMinter, tokenId);
        return IERC721Receiver.onERC721Received.selector;
    }
}
