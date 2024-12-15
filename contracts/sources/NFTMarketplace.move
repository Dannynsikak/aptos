// TODO# 1: Define Module and Marketplace Address
address 0x05e7fb6f3e268373bb1524c366b5cabb66591cbe34d5dde0bf94542922520e6e{

    module NFTMarketplace {
        use 0x1::signer;
        use 0x1::vector;
        use 0x1::coin;
        use 0x1::aptos_coin;
        use 0x1::timestamp;

        // TODO# 2: Define NFT Structure
        struct NFT has store, key {
            id: u64,
            owner: address,
            name: vector<u8>,
            description: vector<u8>,
            uri: vector<u8>,
            price: u64,
            for_sale: bool,
            rarity: u8 // 1 for common, 2 for rare, 3 for epic, etc.
        }
        
        struct DutchAuction has store, key {
            nft_id: u64,
            seller: address,
            start_price: u64,
            reserve_price: u64,
            duration: u64,
            start_time: u64,
            is_active: bool,
            highest_bid: u64, // new field to track the highest Bid
            highest_bidder: address, // new field to track the highest_bidder
        }


        // TODO# 3: Define Marketplace Structure
        struct Marketplace has key {
            nfts: vector<NFT>
        }

        struct AuctionHouse has store, key {
            auctions: vector<DutchAuction>
        }

        
        // TODO# 4: Define ListedNFT Structure
        struct ListedNFT has copy, drop {
            id: u64,
            price: u64,
            rarity: u8
        }


        // TODO# 5: Set Marketplace Fee
        const MARKETPLACE_FEE_PERCENT: u64 = 2; // 2% fee


        // TODO# 6: Initialize Marketplace    
        public entry fun initialize(account: &signer) {
            let marketplace = Marketplace {
                nfts: vector::empty<NFT>()
            };
            move_to(account, marketplace)
        }

        // TODO# 7: Check Marketplace Initialization
        #[view]
        public fun is_marketplace_intialized(marketplace_addr: address): bool {
            exists<Marketplace>(marketplace_addr)
        }

        // initialize Auction house 
        public entry fun initialize_auction_house(account: &signer) {
            assert!(!exists<AuctionHouse>(signer::address_of(account)), 600); // Prevent re-initialization
            let auction_house = AuctionHouse {
                auctions: vector::empty<DutchAuction>()
            };
            move_to(account, auction_house);
        }

        #[view]
        public fun is_auction_house_initialized(auction_addr: address): bool {
            exists<AuctionHouse>(auction_addr)
        }

        // list NFT for dutch auction
        public entry fun list_nft_for_auction(
            account: &signer,
            marketplace_addr: address,
            nft_id: u64,
            start_price: u64,
            reserve_price: u64,
            duration: u64
        ) acquires Marketplace, AuctionHouse {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.owner == signer::address_of(account), 100); // Caller must be the owner
            assert!(nft_ref.for_sale == false, 101); // NFT should not already be listed
            assert!(start_price > reserve_price, 102); // Starting price must exceed reserve price

            // lock NFT and mark it as not for sale
            nft_ref.for_sale = false;

            let auction_house = borrow_global_mut<AuctionHouse>(marketplace_addr);
            let current_time = timestamp::now_seconds();

            let auction = DutchAuction {
                nft_id,
                seller: signer::address_of(account),
                start_price,
                reserve_price,
                duration,
                start_time: current_time,
                is_active: true,
                highest_bid: 0, // initialize the highest bid to be 0
                highest_bidder: signer::address_of(account), // initialize highest bidder to the seller or default address
            };

            vector::push_back(&mut auction_house.auctions, auction);
        }

        // Bid on an Auction
        public entry fun bid_on_auction(
            account: &signer,
            marketplace_addr: address,
            auction_id: u64,
            payment: u64
        ) acquires AuctionHouse {
            let auction_house = borrow_global_mut<AuctionHouse>(marketplace_addr);
            let auction_ref = vector::borrow_mut(&mut auction_house.auctions, auction_id);

            assert!(auction_ref.is_active, 200); // auction must be active
            let current_time = timestamp::now_seconds();
            assert!(current_time < auction_ref.start_time + auction_ref.duration, 201); // Auction not expired

            // calculate current price
            let elapsed_time = current_time - auction_ref.start_time;
            let price_drop = (auction_ref.start_price - auction_ref.reserve_price) * elapsed_time / auction_ref.duration;
            let current_price = auction_ref.start_price - price_drop;

            assert!(payment >= current_price, 202); // payment must meet or exceed current price

            // update highest bid and bidder
            auction_ref.highest_bid = payment;
            auction_ref.highest_bidder = signer::address_of(account); // Track the current highest bidder
        }

        // finalize auction 
        public entry fun finalize_auction(
            account: &signer,
            marketplace_addr: address,
            auction_id: u64
        ) acquires AuctionHouse, Marketplace {
            // Borrow the AuctionHouse resource for the given marketplace address
            let auction_house = borrow_global_mut<AuctionHouse>(marketplace_addr);

            //validate the auctionID and borrow a mutable refrence to the auction
            assert!(auction_id < vector::length(&auction_house.auctions), 301); // Invalid auction id

            let auction_ref = vector::borrow_mut(&mut auction_house.auctions, auction_id);

            // Ensure the auction has ended
            let current_time = timestamp::now_seconds();
            assert!(current_time >= auction_ref.start_time + auction_ref.duration, 300); // auction has not ended yet
            
            // proceed only if the auction is active
            if (auction_ref.is_active) {
                let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
                // Validate the NFT ID and borrow a mutable reference to the NFT
                assert!(
                    auction_ref.nft_id < vector::length(&marketplace.nfts),
                    302 // Invalid NFT ID
                );
                let nft_ref = vector::borrow_mut(&mut marketplace.nfts, auction_ref.nft_id);

                if (auction_ref.highest_bid > 0) {
                    // transfer ownership to the highest bidder 
                    nft_ref.owner = auction_ref.highest_bidder;
                    nft_ref.for_sale = false;

                    // calculate markeplace fee
                    let fee = (auction_ref.highest_bid * MARKETPLACE_FEE_PERCENT) / 100;
                    let seller_revenue = auction_ref.highest_bid - fee;

                    // transfer funds
                    coin::transfer<aptos_coin::AptosCoin>(account, marketplace_addr, fee); // fee to marketplace
                    coin::transfer<aptos_coin::AptosCoin>(account, auction_ref.seller, seller_revenue); // reserve to seller 
                } else {
                    // return NFT to the seller if no bids were placed
                    nft_ref.owner = auction_ref.seller;
                    nft_ref.for_sale = false;
                };

                // mark auction as inactive
                auction_ref.is_active = false;
            }
        }

        // retrieve active auctions
        #[view]
        public fun get_active_auctions(marketplace_addr: address): vector<u64> acquires AuctionHouse {
            let auction_house = borrow_global<AuctionHouse>(marketplace_addr);
            let active_auction_ids = vector::empty<u64>();

            let auction_len = vector::length(&auction_house.auctions);

            let mut_i = 0;
            while (mut_i < auction_len) {
                let auction = vector::borrow(&auction_house.auctions, mut_i);
                if (auction.is_active) {
                    vector::push_back(&mut active_auction_ids, auction.nft_id);
                };
                mut_i = mut_i + 1;
            };
            active_auction_ids
        }



        // TODO# 8: Mint New NFT
         public entry fun mint_nft(account: &signer, name: vector<u8>, description: vector<u8>, uri: vector<u8>, rarity: u8) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(signer::address_of(account));
            let nft_id = vector::length(&marketplace.nfts);

            let new_nft = NFT {
                id: nft_id,
                owner: signer::address_of(account),
                name,
                description,
                uri,
                price: 0,
                for_sale: false,
                rarity
            };

            vector::push_back(&mut marketplace.nfts, new_nft);
        }

        // TODO# 9: View NFT Details
        #[view]
        public fun get_nft_details(marketplace_addr: address, nft_id: u64): (u64, address, vector<u8>,vector<u8>, vector<u8>, u64, bool, u8) acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);

            (nft.id, nft.owner, nft.name, nft.description, nft.uri,nft.price, nft.for_sale, nft.rarity)
        }

        
        // TODO# 10: List NFT for Sale
        public entry fun list_for_sale(account: &signer, marketplace_addr: address, nft_id: u64, price: u64) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.owner == signer::address_of(account), 100); // Caller is not the owner
            assert!(!nft_ref.for_sale, 101); // NFT is already listed
            assert!(price > 0, 102); // Invalid price

            nft_ref.for_sale = true;
            nft_ref.price = price;
        }


        // TODO# 11: Update NFT Price
         public entry fun set_price(account: &signer, marketplace_addr: address, nft_id: u64, price: u64) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.owner == signer::address_of(account), 200); // Caller is not the owner
            assert!(price > 0, 201); // Invalid price

            nft_ref.price = price;
        }


        // TODO# 12: Purchase NFT
         public entry fun purchase_nft(account: &signer, marketplace_addr: address, nft_id: u64, payment: u64) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.for_sale, 400); // NFT is not for sale
            assert!(payment >= nft_ref.price, 401); // Insufficient payment

            // Calculate marketplace fee
            let fee = (nft_ref.price * MARKETPLACE_FEE_PERCENT) / 100;
            let seller_revenue = payment - fee;

            // Transfer payment to the seller and fee to the marketplace
            coin::transfer<aptos_coin::AptosCoin>(account, marketplace_addr, fee);
            coin::transfer<aptos_coin::AptosCoin>(account, signer::address_of(account), seller_revenue);

            // Transfer ownership
            nft_ref.owner = signer::address_of(account);
            nft_ref.for_sale = false;
            nft_ref.price = 0;
        }


        // TODO# 13: Check if NFT is for Sale
        #[view]
        public fun is_nft_for_sale(marketplace_addr: address, nft_id: u64): bool acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);
            nft.for_sale
        }


        // TODO# 14: Get NFT Price
        #[view]
        public fun get_nft_price(marketplace_addr: address, nft_id: u64): u64 acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);
            nft.price
        }


        // TODO# 15: Transfer Ownership
          public entry fun transfer_ownership(account: &signer, marketplace_addr: address, nft_id: u64, new_owner: address) acquires Marketplace {
            let marketplace = borrow_global_mut<Marketplace>(marketplace_addr);
            let nft_ref = vector::borrow_mut(&mut marketplace.nfts, nft_id);

            assert!(nft_ref.owner == signer::address_of(account), 300); // Caller is not the owner
            assert!(nft_ref.owner != new_owner, 301); // Prevent transfer to the same owner

            // Update NFT ownership and reset its for_sale status and price
            nft_ref.owner = new_owner;
            nft_ref.for_sale = false;
            nft_ref.price = 0;
        }


        // TODO# 16: Retrieve NFT Owner
        #[view]
        public fun get_owner(marketplace_addr: address, nft_id: u64): address acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft = vector::borrow(&marketplace.nfts, nft_id);
            nft.owner
        }


        // TODO# 17: Retrieve NFTs for Sale
        #[view]
        public fun get_all_nfts_for_owner(marketplace_addr: address, owner_addr: address, limit: u64, offset: u64): vector<u64> acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft_ids = vector::empty<u64>();

            let nfts_len = vector::length(&marketplace.nfts);
            let end = min(offset + limit, nfts_len);
            let mut_i = offset;
            while (mut_i < end) {
                let nft = vector::borrow(&marketplace.nfts, mut_i);
                if (nft.owner == owner_addr) {
                    vector::push_back(&mut nft_ids, nft.id);
                };
                mut_i = mut_i + 1;
            };

            nft_ids
        }
 

        // TODO# 18: Retrieve NFTs for Sale
         #[view]
        public fun get_all_nfts_for_sale(marketplace_addr: address, limit: u64, offset: u64): vector<ListedNFT> acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nfts_for_sale = vector::empty<ListedNFT>();

            let nfts_len = vector::length(&marketplace.nfts);
            let end = min(offset + limit, nfts_len);
            let mut_i = offset;
            while (mut_i < end) {
                let nft = vector::borrow(&marketplace.nfts, mut_i);
                if (nft.for_sale) {
                    let listed_nft = ListedNFT { id: nft.id, price: nft.price, rarity: nft.rarity };
                    vector::push_back(&mut nfts_for_sale, listed_nft);
                };
                mut_i = mut_i + 1;
            };

            nfts_for_sale
        }


        // TODO# 19: Define Helper Function for Minimum Value
         
        // Helper function to find the minimum of two u64 numbers
        public fun min(a: u64, b: u64): u64 {
            if (a < b) { a } else { b }
        }


        // TODO# 20: Retrieve NFTs by Rarity
        // New function to retrieve NFTs by rarity
        #[view]
        public fun get_nfts_by_rarity(marketplace_addr: address, rarity: u8): vector<u64> acquires Marketplace {
            let marketplace = borrow_global<Marketplace>(marketplace_addr);
            let nft_ids = vector::empty<u64>();

            let nfts_len = vector::length(&marketplace.nfts);
            let mut_i = 0;
            while (mut_i < nfts_len) {
                let nft = vector::borrow(&marketplace.nfts, mut_i);
                if (nft.rarity == rarity) {
                    vector::push_back(&mut nft_ids, nft.id);
                };
                mut_i = mut_i + 1;
            };

            nft_ids
        }
    }
}
