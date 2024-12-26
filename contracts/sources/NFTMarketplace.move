// TODO# 1: Define Module and Marketplace Address
address  0x9be9521129d83f8763fa73debaa043e789cfe9096e191d68c39a8e0afdb1e960 {

    module NFTMarketplace {
        use std::error;
        use std::string::{Self, String};
        use std::option;
        use std::signer;
        use std::vector;
        use 0x1::coin;
        use 0x1::aptos_coin;
        use 0x1::timestamp;
        use aptos_token_objects::token::{Self, Token};
        use aptos_framework::event;
        use aptos_framework::object::{Self, Object, TransferRef};
        use aptos_framework::fungible_asset::{Metadata};
        use aptos_framework::primary_fungible_store;
        use aptos_token_objects::collection::Collection;
        use aptos_token_objects::collection;



        const ENOT_OWNER: u64 = 1;
        const ETOKEN_SOLD: u64 = 2;
        const EINVALID_AUCTION_OBJECT: u64 = 3;
        const EOUTDATED_AUCTION: u64 = 4;
        const EINVALID_PRICES: u64 = 5;
        const EINVALID_DURATION: u64 = 6;
        const DUTCH_AUCTION_COLLECTION_NAME: vector<u8> = b"DUTCH_AUCTION_NAME";
        const DUTCH_AUCTION_COLLECTION_DESCRIPTION: vector<u8> = b"DUTCH_AUCTION_DESCRIPTION";
        const DUTCH_AUCTION_COLLECTION_URI: vector<u8> = b"DUTCH_AUCTION_URI";

        const DUTCH_AUCTION_SEED_PREFIX: vector<u8> = b"AUCTION_SEED_PREFIX";
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
        #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
        struct DutchAuction has drop, store, key {
            _nft_id: u64,
            description: vector<u8>,
            owner: address,
            uri: vector<u8>,
        }
        struct AuctionHouse has key {
            sell_token: Object<Token>,
            duration: u64,
            buy_token: Object<Metadata>,
            max_price: u64,
            min_price: u64,
            started_at: u64,
        }

        struct Auction has key {
            auction_house: Object<AuctionHouse>,
            token_config: Object<TokenConfig>,
        }

        #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
        struct TokenConfig has key, drop {
            transfer_ref: TransferRef
        }
        
       
        // TODO# 3: Define Marketplace Structure
        struct Marketplace has key {
            nfts: vector<NFT>
        }
        #[event]
        struct AuctionCreated has drop, store {
            auction: Object<AuctionHouse>
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
            let description = string::utf8(DUTCH_AUCTION_COLLECTION_DESCRIPTION);
            let name = string::utf8(DUTCH_AUCTION_COLLECTION_NAME);
            let uri = string::utf8(DUTCH_AUCTION_COLLECTION_URI);

            collection::create_unlimited_collection(account, description, name, option::none(),uri);
        }

        #[view]
        public fun is_auction_house_initialized(auction_addr: address): bool {
            exists<AuctionHouse>(auction_addr)
        }

        // list NFT for dutch auction
       public entry fun list_nft_for_auction(
            owner: &signer,
            name: String,
            description: String,
            uri: String,
            buy_token: Object<Metadata>,
            max_price: u64,
            min_price: u64,
            duration: u64
        ) {
            only_owner(owner, signer::address_of(owner));
            assert!(max_price >= min_price, error::invalid_argument(EINVALID_PRICES));
            assert!(duration > 0, error::invalid_argument(EINVALID_DURATION));
            
            let collection_name = string::utf8(DUTCH_AUCTION_COLLECTION_NAME);

            let sell_token_ctor = token::create_named_token(
                owner,
                collection_name,
                description,
                name,
                option::none(),
                uri,
            );
            let sell_token = object::object_from_constructor_ref<Token>(&sell_token_ctor);
            object::move_to_named(owner, sell_token);

            let auction = AuctionHouse {
                sell_token,
                buy_token,
                max_price,
                min_price,
                duration,
                started_at: timestamp::now_seconds(),
            };
            let auction_seed = get_auction_seed(name);
            let auction_ctor = object::create_named_object(owner,auction_seed);
            let auction_signer = object::generate_signer(&auction_ctor);

            let transfer_ref = object::generate_transfer_ref(&auction_ctor);
            move_to(&auction_signer, auction);
            move_to(&auction_signer, TokenConfig { transfer_ref });
            let transfer_ref = object::generate_transfer_ref(&auction_ctor);
            move_to(&auction_signer, TokenConfig { transfer_ref });
            let auction = object::object_from_constructor_ref<AuctionHouse>(&auction_ctor);
            event::emit(AuctionCreated {auction});
        }
        fun get_collection_seed(): vector<u8> {
            DUTCH_AUCTION_COLLECTION_NAME
        }

        fun get_token_seed(name: String): vector<u8> {
            let collection_name = string::utf8(DUTCH_AUCTION_COLLECTION_NAME);

            // concatenates collection_name::token_name
            token::create_token_seed(&collection_name, &name)
        }
        fun get_auction_seed(name: String): vector<u8> {
            let token_seed = get_token_seed(name);
            let seed = DUTCH_AUCTION_SEED_PREFIX;
            vector::append(&mut seed, b"::");
            vector::append(&mut seed, token_seed);

            seed
        }

        inline fun only_owner(owner: &signer , addr: address) {
            assert!(signer::address_of(owner) == addr, error::permission_denied(ENOT_OWNER) )
        }

        // Bid on an Auction
        public entry fun bid_on_auction(
            customer: &signer, auction: Object<AuctionHouse>
        ) acquires AuctionHouse, TokenConfig {
            let auction_address = object::object_address(&auction);
            let auction = borrow_global_mut<AuctionHouse>(auction_address);

            assert!(exists<TokenConfig>(auction_address), error::unavailable(ETOKEN_SOLD));

            let current_price = must_have_price(auction);

            primary_fungible_store::transfer(customer, auction.buy_token, auction_address, current_price);

            let transfer_ref = &borrow_global_mut<TokenConfig>(auction_address).transfer_ref;
            let linear_transfer_ref = object::generate_linear_transfer_ref(transfer_ref);

            object::transfer_with_ref(linear_transfer_ref, signer::address_of(customer));

            move_from<TokenConfig>(auction_address);
        }

        fun must_have_price(auction: &AuctionHouse): u64 {
            let time_now = timestamp::now_seconds();

            assert!(time_now <= auction.started_at + auction.duration, error::unavailable(EOUTDATED_AUCTION));

            let time_passed = time_now - auction.started_at;
            let discount = ((auction.max_price - auction.min_price) * time_passed) / auction.duration;

            auction.max_price - discount
        }

        // retrieve active auctions
    #[view]
    public fun get_auction_object(name: String, owner_addr: address): Object<AuctionHouse> {
        let auction_seed = get_auction_seed(name);
        let auction_address = object::create_object_address(&owner_addr, auction_seed);

        object::address_to_object(auction_address)
    }
        #[view]
        public fun get_collection_object(owner_addr: address): Object<Collection> {
            let collection_seed = get_collection_seed();
            let collection_address = object::create_object_address(&owner_addr, collection_seed);

            object::address_to_object(collection_address)
        }

        #[view]
        public fun get_token_object(name: String, owner_addr: address): Object<Token> {
            let token_seed = get_token_seed(name);
            let token_object = object::create_object_address(&owner_addr, token_seed);

            object::address_to_object<Token>(token_object)
        }

        #[view]
        public fun get_auction(auction_object: Object<AuctionHouse>): AuctionHouse acquires AuctionHouse {
            let auction_address = object::object_address(&auction_object);
            let auction = borrow_global<AuctionHouse>(auction_address);

            AuctionHouse {
                sell_token: auction.sell_token,
                buy_token: auction.buy_token,
                max_price: auction.max_price,
                min_price: auction.min_price,
                duration: auction.duration,
                started_at: auction.started_at
            }
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
        #[test(aptos_framework = @0x1, owner = @0x2, customer = @0x1234)]
        fun test_auction_happy_path(
            aptos_framework: &signer,
            owner: &signer,
            customer: &signer
        ) acquires TokenConfig, AuctionHouse {
            initialize(owner);

            timestamp::set_time_has_started_for_testing(aptos_framework);
            timestamp::update_global_time_for_test_secs(1000);

            let buy_token = setup_buy_token(owner, customer);

            let name = string::utf8(b"name");
            let description = string::utf8(b"description");
            let uri = string::utf8(b"uri");
            let max_price = 10;
            let min_price = 1;
            let duration = 300;

            list_nft_for_auction(
                owner,
                name,
                description,
                uri,
                buy_token,
                max_price,
                min_price,
                duration
            );

            let token = get_token_object(name, signer::address_of(owner));

            assert!(object::is_owner(token, signer::address_of(owner)), 1);

            let auction_created_events = event::emitted_events<AuctionCreated>();
            let auction = vector::borrow(&auction_created_events, 0).auction;

            assert!(auction == get_auction_object(name, signer::address_of(owner)), 1);
            assert!(primary_fungible_store::balance(signer::address_of(customer), buy_token) == 50, 1);

        bid_on_auction(customer, auction);

        assert!(object::is_owner(token, signer::address_of(customer)), 1);
        assert!(primary_fungible_store::balance(signer::address_of(customer), buy_token) == 40, 1);
    }

    #[test_only]
    fun setup_buy_token(owner: &signer, customer: &signer): Object<Metadata> {
        use aptos_framework::fungible_asset;

        let ctor_ref = object::create_sticky_object(signer::address_of(owner));

        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &ctor_ref,
            option::none<u128>(),
            string::utf8(b"token"),
            string::utf8(b"symbol"),
            0,
            string::utf8(b"icon_uri"),
            string::utf8(b"project_uri")
        );

        let metadata = object::object_from_constructor_ref<Metadata>(&ctor_ref);
        let mint_ref = fungible_asset::generate_mint_ref(&ctor_ref);

        let customer_store = primary_fungible_store::ensure_primary_store_exists(
            signer::address_of(customer),
            metadata
        );

        fungible_asset::mint_to(&mint_ref, customer_store, 50);

        metadata
    }
    }
}
