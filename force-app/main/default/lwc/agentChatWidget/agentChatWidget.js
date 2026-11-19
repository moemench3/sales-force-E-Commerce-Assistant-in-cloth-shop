import { LightningElement, track } from 'lwc';
import sendMessageToAgent from '@salesforce/apex/AgentChatController.sendMessageToAgent';
import createSalesforceOrder from '@salesforce/apex/AgentChatController.createSalesforceOrder';
import getUserOrders from '@salesforce/apex/AgentChatController.getUserOrders';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class AgentChatWidget extends LightningElement {
    userInput = '';
    @track messages = [];
    isModalOpen = false;
    isCartOpen = false;
    isWishlistOpen = false; // State to control Wishlist modal visibility
    selectedProduct = {};
    selectedSize = 'M';
    selectedPaymentMethod = 'Cash on Delivery';
    isLoading = false;
    @track cart = [];
    @track wishlist = [];
    isOrdersOpen = false;
    userOrders = [];
    fallbackImage = '/resource/FallbackProductImage';

    // Maximum allowed quantity per product
    MAX_PIECES_PER_PRODUCT = 3;

    // Interactive Star Rating Tracker
    userRating = 0;

    // Size Calculator Reactive Properties
    isSizeCalcOpen = false;
    userHeight = '';
    userWeight = '';
    recommendedSize = '';

    // Currency & Exchange Rate State
    selectedCurrency = 'USD';
    exchangeRate = 1;

    // الخيارات الخاصة بالقائمة المنسدلة
    sortOptions = [
        { label: 'Featured', value: 'default' },
        { label: 'Price: Low to High', value: 'price-asc' },
        { label: 'Price: High to Low', value: 'price-desc' },
        { label: 'Highest Rated', value: 'rating-desc' }
    ];

    // AI Suggested Prompts Chips Data
    suggestedPrompts = [
        { id: 'p1', label: 'show me all products', value: 'show all products' },
        { id: 'p3', label: 'show me all shirts', value: 'show me all shirts' },
        { id: 'p4', label: 'show me all shoes', value: 'show me all shoes' },
        { id: 'p5', label: 'show me all pants', value: 'show me all pants' }
    ];

    sessionId = '';
    previousMessageCount = 0;

    resolveImageUrl(identifier) {
        if (!identifier) return this.fallbackImage;
        const cleanKey = String(identifier).trim();

        if (
            cleanKey.startsWith('data:') ||
            cleanKey.startsWith('http://') ||
            cleanKey.startsWith('https://') ||
            cleanKey.startsWith('/sfc/')
        ) {
            return cleanKey;
        }

        if (cleanKey.startsWith('068')) {
            return `/sfc/servlet.shepherd/version/download/${cleanKey}`;
        }

        if (cleanKey.startsWith('069')) {
            return `/sfc/servlet.shepherd/document/download/${cleanKey}`;
        }

        return this.fallbackImage;
    }

    connectedCallback() {
        this.loadOrdersFromDatabase();
    }

    renderedCallback() {
        if (this.messages.length !== this.previousMessageCount) {
            this.previousMessageCount = this.messages.length;
            this.scrollToBottom();
        }
    }

    loadOrdersFromDatabase() {
        getUserOrders()
            .then(result => {
                this.userOrders = result || [];
            })
            .catch(error => {
                console.error('Error fetching orders from DB:', error);
            });
    }

    openOrders() {
        this.isOrdersOpen = true;
        this.loadOrdersFromDatabase();
    }

    closeOrders() {
        this.isOrdersOpen = false;
    }

    get hasOrders() {
        return this.userOrders && this.userOrders.length > 0;
    }

    get ordersCount() {
        return this.userOrders ? this.userOrders.length : 0;
    }

    scrollToBottom() {
        const chatContainer = this.template.querySelector('.chat-messages-container');
        if (chatContainer) {
            chatContainer.scrollTop = chatContainer.scrollHeight;
        }
    }

    get hasSuggestedPrompts() {
        return this.suggestedPrompts && this.suggestedPrompts.length > 0;
    }

    handlePromptChipClick(event) {
        const promptText = event.currentTarget.dataset.prompt;
        this.userInput = promptText;
        this.handleSend();
    }

    get currencyOptions() {
        return [
            { label: 'USD ($)', value: 'USD' },
            { label: 'EUR (€)', value: 'EUR' },
            { label: 'LBP (L.L.)', value: 'LBP' }
        ];
    }

    get currencySymbol() {
        if (this.selectedCurrency === 'EUR') return '€';
        if (this.selectedCurrency === 'LBP') return 'L.L. ';
        return '$';
    }

    handleCurrencyChange(event) {
        this.selectedCurrency = event.detail.value;
        if (this.selectedCurrency === 'USD') {
            this.exchangeRate = 1;
        } else if (this.selectedCurrency === 'EUR') {
            this.exchangeRate = 0.92;
        } else if (this.selectedCurrency === 'LBP') {
            this.exchangeRate = 89500;
        }
        this.refreshWishlistPrices();
    }

    handleRateChange(event) {
        const val = parseFloat(event.target.value);
        this.exchangeRate = val && val > 0 ? val : 1;
        this.refreshWishlistPrices();
    }

    formatPrice(amountInUSD) {
        const converted = (parseFloat(amountInUSD) || 0) * this.exchangeRate;
        if (this.selectedCurrency === 'LBP') {
            return this.currencySymbol + Math.round(converted).toLocaleString();
        }
        return this.currencySymbol + converted.toFixed(2);
    }

    refreshWishlistPrices() {
        this.wishlist = this.wishlist.map(w => ({
            ...w,
            formattedPrice: this.formatPrice(w.price || w.Price__c || 0)
        }));
    }

    get sizeOptions() {
        return [
            { label: 'Extra Small (XS)', value: 'XS' },
            { label: 'Small (S)', value: 'S' },
            { label: 'Medium (M)', value: 'M' },
            { label: 'Large (L)', value: 'L' },
            { label: 'Extra Large (XL)', value: 'XL' }
        ];
    }

    get paymentOptions() {
        return [
            { label: 'Cash on Delivery', value: 'Cash on Delivery' },
            { label: 'Credit Card', value: 'Credit Card' },
            { label: 'PayPal', value: 'PayPal' }
        ];
    }

    get star1Style() { return `color: ${this.userRating >= 1 ? '#f59e0b' : '#cbd5e1'}; font-size: 1.8rem; cursor: pointer; transition: transform 0.15s, color 0.15s; display: inline-block;`; }
    get star2Style() { return `color: ${this.userRating >= 2 ? '#f59e0b' : '#cbd5e1'}; font-size: 1.8rem; cursor: pointer; transition: transform 0.15s, color 0.15s; display: inline-block;`; }
    get star3Style() { return `color: ${this.userRating >= 3 ? '#f59e0b' : '#cbd5e1'}; font-size: 1.8rem; cursor: pointer; transition: transform 0.15s, color 0.15s; display: inline-block;`; }
    get star4Style() { return `color: ${this.userRating >= 4 ? '#f59e0b' : '#cbd5e1'}; font-size: 1.8rem; cursor: pointer; transition: transform 0.15s, color 0.15s; display: inline-block;`; }
    get star5Style() { return `color: ${this.userRating >= 5 ? '#f59e0b' : '#cbd5e1'}; font-size: 1.8rem; cursor: pointer; transition: transform 0.15s, color 0.15s; display: inline-block;`; }

    get cartItemsCount() { return this.cart.reduce((acc, item) => acc + item.quantity, 0); }
    get wishlistItemsCount() { return this.wishlist.length; }
    get hasCartItems() { return this.cart.length > 0; }
    get isCartEmpty() { return this.cart.length === 0; }
    get hasWishlistItems() { return this.wishlist.length > 0; }

    get cartGrandTotal() {
        const totalUSD = this.cart.reduce((sum, item) => sum + (item.price * item.quantity), 0);
        return this.formatPrice(totalUSD);
    }

    get formattedCartItems() {
        return this.cart.map(item => ({
            ...item,
            formattedPrice: this.formatPrice(item.price),
            formattedTotal: this.formatPrice(item.price * item.quantity)
        }));
    }

    get selectedProductFormattedPrice() {
        return this.formatPrice(this.selectedProduct ? (this.selectedProduct.price || this.selectedProduct.Price__c || 0) : 0);
    }

    get isModalProductOutOfStock() {
        return !this.selectedProduct || this.selectedProduct.stockCount <= 0;
    }

    handleInputChange(event) {
        this.userInput = event.target.value;
    }

    handleKeyUp(event) {
        if (event.keyCode === 13) this.handleSend();
    }

    handleSetRating(event) {
        const selectedStars = parseInt(event.currentTarget.dataset.value, 10);
        this.userRating = selectedStars;

        this.selectedProduct = { ...this.selectedProduct, rating: selectedStars };
        const targetId = String(this.selectedProduct.id);

        this.messages = this.messages.map(msg => {
            if (!msg.products) return msg;
            const updatedProds = msg.products.map(p =>
                String(p.id) === targetId ? { ...p, rating: selectedStars } : p
            );
            return { ...msg, products: updatedProds };
        });

        this.wishlist = this.wishlist.map(w =>
            String(w.id) === targetId ? { ...w, rating: selectedStars } : w
        );

        this.showToast('Rating Saved', `You rated this product ${selectedStars} star(s)!`, 'success');
    }

    cleanReplyText(text) {
        if (!text) return '';
        // تنظيف النص العلوي من الأقواس المزدوجة وروابط الصور العارية
        return text
            .replace(/\[\[.*?\]\]/g, '')
            .replace(/\/sfc\/servlet\.shepherd\/[^\s]+/g, '')
            .replace(/\s+/g, ' ')
            .trim();
    }
    parseProductsFromText(text) {
        if (!text) return [];
        const products = [];

        const productRegex = /(?:Product:\s*)?([^\n\r\[\]]+?)\s*\[\[(.*?)\]\](?:[^\n\r]*?(?:Price:?\s*)?\$?\s*([\d\.]+))?/gi;
        let match;

        while ((match = productRegex.exec(text)) !== null) {
            let pName = match[1] ? match[1].trim() : 'Store Product';
            const pCode = match[2] ? match[2].trim() : '';

            pName = pName.replace(/^Product:\s*/i, '').trim();

            let pPrice = 0;
            if (match[3]) {
                pPrice = parseFloat(match[3]);
            } else {
                const subChunk = text.slice(match.index, match.index + 120);
                const priceMatch = subChunk.match(/\$\s*([\d\.]+)/);
                if (priceMatch) {
                    pPrice = parseFloat(priceMatch[1]);
                }
            }

            if (!pCode) continue;

            // --- استخراج الـ Stock الديناميكي من نص الـ Flow ---
            let pStock = 0;
            const subChunk = text.slice(match.index, match.index + 200);
            const stockMatch = subChunk.match(/(?:Stock|Qty|Quantity):\s*(\d+)/i);
            if (stockMatch && stockMatch[1]) {
                pStock = parseInt(stockMatch[1], 10);
            }

            const imgRegex = new RegExp(`/sfc/servlet\\.shepherd/version/download/([a-zA-Z0-9]+)`, 'i');
            const imgMatch = text.slice(match.index).match(imgRegex);
            const imgUrl = imgMatch ? imgMatch[0] : pCode;

            products.push({
                id: pCode,
                code: pCode,
                name: pName,
                price: pPrice,
                imageUrl: this.resolveImageUrl(imgUrl),
                stockCount: pStock,              // القيمة الديناميكية من الداتابيز
                hasStock: pStock > 0,
                rating: 0
            });
        }
        return products;
    }

    handleSend() {
        if (!this.userInput || !this.userInput.trim()) return;

        const userMsg = this.userInput.trim();
        this.messages = [
            ...this.messages,
            { id: Date.now(), text: userMsg, cssClass: 'user-message-container' }
        ];
        this.userInput = '';
        this.isLoading = true;
        this.scrollToBottom();

        const cleanCart = this.cart.map(item => ({
            id: item.id,
            name: item.name,
            code: item.code,
            price: item.price,
            quantity: item.quantity,
            size: item.size
        }));

        sendMessageToAgent({
            userMessage: userMsg,
            sessionId: this.sessionId,
            cartJson: JSON.stringify(cleanCart)
        })
            .then(result => {
                const resData = typeof result === 'string' ? JSON.parse(result) : result;
                console.log('--- Raw Agent Text ---', resData);

                if (resData.isSuccess === false) {
                    this.showToast('Error', resData.errorMessage || 'Failed to process message', 'error');
                    return;
                }

                if (resData.sessionId) {
                    this.sessionId = resData.sessionId;
                }

                let rawReplyText = resData.reply || resData.agentReplyText || '';
                let rawProducts = Array.isArray(resData.products) && resData.products.length > 0
                    ? resData.products
                    : [];
                console.log('--- Raw Reply Text ---', rawReplyText);
                console.log('--- Raw Products ---', rawProducts);

                // إذا لم ترجع قائمة منتجات جاهزة من Apex، نفحص النص ونستخرج المنتجات والروابط منه ديناميكياً
                if (rawProducts.length === 0) {
                    rawProducts = this.parseProductsFromText(rawReplyText);
                }

                let cleanedReplyText = this.cleanReplyText(rawReplyText);
                let formattedProducts = null;

                if (rawProducts.length > 0) {
                    formattedProducts = rawProducts.map((p, index) => {
                        const isLiked = this.wishlist.some(w =>
                            (w.id && p.id && String(w.id) === String(p.id)) ||
                            (w.code && p.code && String(w.code) === String(p.code))
                        );

                        const currentStock = p.stockCount !== undefined
                            ? p.stockCount
                            : (p.Stock_Quantity__c !== undefined ? p.Stock_Quantity__c : (p.Stock__c !== undefined ? p.Stock__c : 0));

                        const currentRating = p.rating || p.Rating__c || 0;
                        const agentImageUrl = p.imageUrl || p.image_url || p.Image_Url__c || p.Image_Id__c || p.code || p.id;
                        const resolvedImg = this.resolveImageUrl(agentImageUrl);

                        return {
                            ...p,
                            originalIndex: index,   // أضف هذا السطر
                            imageUrl: resolvedImg,
                            formattedPrice: this.formatPrice(p.price || p.Price__c || 0),
                            stockCount: currentStock,
                            hasStock: currentStock > 0,
                            rating: currentRating,
                            likeClass: isLiked ? 'like-btn is-liked' : 'like-btn'
                        };
                    });
                }

                this.messages = [
                    ...this.messages,
                    {
                        id: Date.now() + 1,
                        text: cleanedReplyText,
                        products: formattedProducts,
                        showOptions: resData.showOptions || false,
                        cssClass: 'agent-message-container'
                    }
                ];
            })
            .catch(error => {
                console.error('Error invoking Apex:', error);
                const errMsg = error.body ? error.body.message : (error.message || 'Error sending message');
                this.showToast('Error', errMsg, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleToggleLike(event) {
        event.stopPropagation();
        const prodId = event.currentTarget.dataset.id;
        let targetProduct = null;

        for (let msg of this.messages) {
            if (msg.products) {
                const found = msg.products.find(p => String(p.id) === String(prodId) || (p.code && String(p.code) === String(prodId)));
                if (found) { targetProduct = found; break; }
            }
        }

        if (!targetProduct) {
            targetProduct = this.wishlist.find(w => String(w.id) === String(prodId) || (w.code && String(w.code) === String(prodId)));
        }

        if (!targetProduct) return;

        const existsIndex = this.wishlist.findIndex(w => String(w.id) === String(prodId) || (w.code && String(w.code) === String(prodId)));
        if (existsIndex > -1) {
            this.wishlist = this.wishlist.filter(w => String(w.id) !== String(prodId) && String(w.code) !== String(prodId));
            this.showToast('Removed', 'Product removed from Wishlist', 'info');
        } else {
            const formattedItem = {
                ...targetProduct,
                formattedPrice: targetProduct.formattedPrice || this.formatPrice(targetProduct.price || targetProduct.Price__c || 0),
                imageUrl: targetProduct.imageUrl || this.resolveImageUrl(targetProduct.code || targetProduct.id)
            };
            this.wishlist = [...this.wishlist, formattedItem];
            this.showToast('Liked!', 'Product added to Wishlist ❤️', 'success');
        }

        this.messages = this.messages.map(msg => {
            if (!msg.products) return msg;
            const updatedProds = msg.products.map(p => {
                const isLiked = this.wishlist.some(w =>
                    (w.id && p.id && String(w.id) === String(p.id)) ||
                    (w.code && p.code && String(w.code) === String(p.code))
                );
                return { ...p, likeClass: isLiked ? 'like-btn is-liked' : 'like-btn' };
            });
            return { ...msg, products: updatedProds };
        });
    }

    removeFromWishlist(event) {
        const prodId = event.currentTarget.dataset.id;
        this.wishlist = this.wishlist.filter(w => String(w.id) !== String(prodId) && String(w.code) !== String(prodId));

        this.messages = this.messages.map(msg => {
            if (!msg.products) return msg;
            const updatedProds = msg.products.map(p => {
                const isLiked = this.wishlist.some(w =>
                    (w.id && p.id && String(w.id) === String(p.id)) ||
                    (w.code && p.code && String(w.code) === String(p.code))
                );
                return { ...p, likeClass: isLiked ? 'like-btn is-liked' : 'like-btn' };
            });
            return { ...msg, products: updatedProds };
        });

        this.showToast('Removed', 'Item removed from Wishlist', 'info');
    }

    handleQuickOption(event) {
        const action = event.target.dataset.action;
        this.userInput = action === 'yes' ? 'نعم، أريد تسجيل طلب' : 'لا، شكراً';
        this.handleSend();
    }

    openModal(event) {
        const prodId = event.currentTarget.dataset.id;
        for (let msg of this.messages) {
            if (msg.products) {
                const found = msg.products.find(p => String(p.id) === String(prodId) || (p.code && String(p.code) === String(prodId)));
                if (found) {
                    this.selectedProduct = { ...found };
                    this.userRating = found.rating || 0;
                    this.selectedSize = 'M';
                    this.isModalOpen = true;
                    return;
                }
            }
        }
        const foundInWishlist = this.wishlist.find(w => String(w.id) === String(prodId) || (w.code && String(w.code) === String(prodId)));
        if (foundInWishlist) {
            this.selectedProduct = { ...foundInWishlist };
            this.userRating = foundInWishlist.rating || 0;
            this.selectedSize = 'M';
            this.isModalOpen = true;
        }
    }

    closeModal() { this.isModalOpen = false; }
    openCart() { this.isCartOpen = true; }
    closeCart() { this.isCartOpen = false; }

    // Wishlist Modal Handlers
    openWishlist = () => {
        console.log('--- Opening Wishlist Modal ---');
        console.log('Wishlist Items:', JSON.parse(JSON.stringify(this.wishlist)));
        this.isWishlistOpen = true;
    };

    closeWishlist = () => {
        console.log('--- Closing Wishlist Modal ---');
        this.isWishlistOpen = false;
    };

    handleSizeChange(event) { this.selectedSize = event.detail.value; }
    handlePaymentChange(event) { this.selectedPaymentMethod = event.detail.value; }

    addToCart() {
        if (!this.selectedProduct || this.selectedProduct.stockCount <= 0) {
            this.showToast('Out of Stock', 'Sorry, this product is out of stock!', 'warning');
            return;
        }

        const itemKey = `${this.selectedProduct.id}_${this.selectedSize}`;
        const existingIndex = this.cart.findIndex(item => item.key === itemKey);
        const currentCartQty = existingIndex > -1 ? this.cart[existingIndex].quantity : 0;

        if (currentCartQty >= this.MAX_PIECES_PER_PRODUCT) {
            this.showToast('Limit Reached', `Maximum limit for each product is ${this.MAX_PIECES_PER_PRODUCT} pieces.`, 'warning');
            return;
        }

        const targetId = String(this.selectedProduct.id);
        const targetCode = this.selectedProduct.code ? String(this.selectedProduct.code) : '';

        this.messages = this.messages.map(msg => {
            if (!msg.products) return msg;
            const updatedProds = msg.products.map(p => {
                const matchById = String(p.id) === targetId;
                const matchByCode = targetCode && p.code && String(p.code) === targetCode;
                if (matchById || matchByCode) {
                    const updatedStock = Math.max(0, p.stockCount - 1);
                    return { ...p, stockCount: updatedStock, hasStock: updatedStock > 0 };
                }
                return p;
            });
            return { ...msg, products: updatedProds };
        });

        this.wishlist = this.wishlist.map(w => {
            const matchById = String(w.id) === targetId;
            const matchByCode = targetCode && w.code && String(w.code) === targetCode;
            if (matchById || matchByCode) {
                const updatedStock = Math.max(0, w.stockCount - 1);
                return { ...w, stockCount: updatedStock, hasStock: updatedStock > 0 };
            }
            return w;
        });

        const updatedSelectedStock = Math.max(0, this.selectedProduct.stockCount - 1);
        this.selectedProduct = {
            ...this.selectedProduct,
            stockCount: updatedSelectedStock,
            hasStock: updatedSelectedStock > 0
        };

        if (existingIndex > -1) {
            this.cart = this.cart.map((item, idx) => {
                if (idx === existingIndex) {
                    const newQty = item.quantity + 1;
                    return {
                        ...item,
                        quantity: newQty,
                        itemTotal: (newQty * item.price).toFixed(2)
                    };
                }
                return item;
            });
        } else {
            this.cart = [...this.cart, {
                key: itemKey,
                id: this.selectedProduct.id,
                name: this.selectedProduct.name,
                code: this.selectedProduct.code,
                price: this.selectedProduct.price || this.selectedProduct.Price__c || 0,
                imageUrl: this.selectedProduct.imageUrl,
                size: this.selectedSize,
                quantity: 1,
                itemTotal: Number(this.selectedProduct.price || this.selectedProduct.Price__c || 0).toFixed(2)
            }];
        }

        this.showToast('Success', `${this.selectedProduct.name} added to cart!`, 'success');
        this.closeModal();
    }

    increaseCartQuantity(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const item = this.cart[index];
        if (!item) return;

        if (item.quantity >= this.MAX_PIECES_PER_PRODUCT) {
            this.showToast('Limit Reached', `Maximum limit for each product is ${this.MAX_PIECES_PER_PRODUCT} pieces.`, 'warning');
            return;
        }

        const targetId = String(item.id);
        const targetCode = item.code ? String(item.code) : '';

        let availableStock = 0;
        for (let msg of this.messages) {
            if (msg.products) {
                const found = msg.products.find(p => String(p.id) === targetId || (targetCode && String(p.code) === targetCode));
                if (found) { availableStock = found.stockCount; break; }
            }
        }

        if (availableStock <= 0) {
            this.showToast('Stock Limit', 'No more stock available for this item.', 'warning');
            return;
        }

        this.messages = this.messages.map(msg => {
            if (!msg.products) return msg;
            const updatedProds = msg.products.map(p => {
                const matchById = String(p.id) === targetId;
                const matchByCode = targetCode && p.code && String(p.code) === targetCode;
                if (matchById || matchByCode) {
                    const updatedStock = Math.max(0, p.stockCount - 1);
                    return { ...p, stockCount: updatedStock, hasStock: updatedStock > 0 };
                }
                return p;
            });
            return { ...msg, products: updatedProds };
        });

        this.cart = this.cart.map((cItem, idx) => {
            if (idx === index) {
                const newQty = cItem.quantity + 1;
                return {
                    ...cItem,
                    quantity: newQty,
                    itemTotal: (newQty * cItem.price).toFixed(2)
                };
            }
            return cItem;
        });
    }

    decreaseCartQuantity(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const item = this.cart[index];
        if (!item) return;

        const targetId = String(item.id);
        const targetCode = item.code ? String(item.code) : '';

        this.messages = this.messages.map(msg => {
            if (!msg.products) return msg;
            const updatedProds = msg.products.map(p => {
                const matchById = String(p.id) === targetId;
                const matchByCode = targetCode && p.code && String(p.code) === targetCode;
                if (matchById || matchByCode) {
                    const restoredStock = p.stockCount + 1;
                    return { ...p, stockCount: restoredStock, hasStock: restoredStock > 0 };
                }
                return p;
            });
            return { ...msg, products: updatedProds };
        });

        this.wishlist = this.wishlist.map(w => {
            const matchById = String(w.id) === targetId;
            const matchByCode = targetCode && w.code && String(w.code) === targetCode;
            if (matchById || matchByCode) {
                const restoredStock = w.stockCount + 1;
                return { ...w, stockCount: restoredStock, hasStock: restoredStock > 0 };
            }
            return w;
        });

        if (item.quantity > 1) {
            this.cart = this.cart.map((cItem, idx) => {
                if (idx === index) {
                    const newQty = cItem.quantity - 1;
                    return {
                        ...cItem,
                        quantity: newQty,
                        itemTotal: (newQty * cItem.price).toFixed(2)
                    };
                }
                return cItem;
            });
        } else {
            this.cart = this.cart.filter((_, idx) => idx !== index);
        }
    }

    removeFromCart(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const itemToRemove = this.cart[index];

        if (!itemToRemove) return;

        const targetId = String(itemToRemove.id);
        const targetCode = itemToRemove.code ? String(itemToRemove.code) : '';
        const qtyToRestore = itemToRemove.quantity;

        this.messages = this.messages.map(msg => {
            if (!msg.products) return msg;
            const updatedProds = msg.products.map(p => {
                const matchById = String(p.id) === targetId;
                const matchByCode = targetCode && p.code && String(p.code) === targetCode;
                if (matchById || matchByCode) {
                    const restoredStock = p.stockCount + qtyToRestore;
                    return { ...p, stockCount: restoredStock, hasStock: restoredStock > 0 };
                }
                return p;
            });
            return { ...msg, products: updatedProds };
        });

        this.wishlist = this.wishlist.map(w => {
            const matchById = String(w.id) === targetId;
            const matchByCode = targetCode && w.code && String(w.code) === targetCode;
            if (matchById || matchByCode) {
                const restoredStock = w.stockCount + qtyToRestore;
                return { ...w, stockCount: restoredStock, hasStock: restoredStock > 0 };
            }
            return w;
        });

        this.cart = this.cart.filter((_, idx) => idx !== index);
        this.showToast('Restored', `Restored ${qtyToRestore} item(s) back to stock.`, 'info');
    }

    handleCheckout() {
        if (this.cart.length === 0) return;

        this.isLoading = true;
        createSalesforceOrder({ cartDataJson: JSON.stringify(this.cart), paymentMethod: this.selectedPaymentMethod })
            .then(orderId => {
                this.showToast('Success!', `Order created successfully! (Order ID: ${orderId})`, 'success');
                this.cart = [];
                this.closeCart();
            })
            .catch(error => {
                this.showToast('Checkout Failed', error.body ? error.body.message : 'Error creating order', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    handleImageError(event) {
        event.target.onerror = null;
        event.target.src = this.fallbackImage;
    }

    handleResetChat() {
        this.messages = [
            {
                id: Date.now(),
                text: 'أهلاً بك مجدداً! كيف يمكنني مساعدتك اليوم؟',
                cssClass: 'agent-message-container'
            }
        ];
        this.sessionId = '';
        this.showToast('New Chat', 'Chat conversation has been reset.', 'info');
    }

    calculateSize() {
        const height = parseFloat(this.userHeight);
        const weight = parseFloat(this.userWeight);

        if (!height || !weight) {
            this.recommendedSize = '';
            return;
        }

        if (height < 160) {
            this.recommendedSize = weight < 50 ? 'XS' : 'S';
        } else if (height >= 160 && height < 168) {
            if (weight < 52) this.recommendedSize = 'XS';
            else if (weight <= 62) this.recommendedSize = 'S';
            else this.recommendedSize = 'M';
        } else if (height >= 168 && height <= 178) {
            if (weight < 60) this.recommendedSize = 'S';
            else if (weight <= 75) this.recommendedSize = 'M';
            else this.recommendedSize = 'L';
        } else if (height > 178 && height <= 188) {
            if (weight < 72) this.recommendedSize = 'M';
            else if (weight <= 85) this.recommendedSize = 'L';
            else this.recommendedSize = 'XL';
        } else {
            this.recommendedSize = weight <= 90 ? 'L' : 'XL';
        }
    }

    openSizeCalculator() {
        this.isSizeCalcOpen = true;
    }

    closeSizeCalculator() {
        this.isSizeCalcOpen = false;
        this.userHeight = '';
        this.userWeight = '';
        this.recommendedSize = '';
    }

    handleHeightChange(event) {
        this.userHeight = event.target.value;
        this.calculateSize();
    }

    handleWeightChange(event) {
        this.userWeight = event.target.value;
        this.calculateSize();
    }

    get isApplySizeDisabled() {
        return !this.recommendedSize;
    }

    applyRecommendedSize() {
        if (this.recommendedSize) {
            this.selectedSize = this.recommendedSize;
            this.showToast('Size Applied', `Selected size set to ${this.recommendedSize}`, 'success');
            this.closeSizeCalculator();
        }
    }
    scrollToBottom() {
        setTimeout(() => {
            const chatArea = this.template.querySelector('.chat-messages');
            if (chatArea) {
                chatArea.scrollTop = chatArea.scrollHeight;
            }
        }, 50);
    }
    handleSortChange(event) {
        const selectedOption = event.detail.value;
        const msgId = event.currentTarget.dataset.msgId;

        this.messages = this.messages.map(msg => {
            if (String(msg.id) !== String(msgId) || !Array.isArray(msg.products)) {
                return msg;
            }

            const sorted = [...msg.products].sort((a, b) => {
                const priceA = Number(a.price ?? a.Price__c ?? 0);
                const priceB = Number(b.price ?? b.Price__c ?? 0);

                switch (selectedOption) {
                    case 'price-asc':
                        return priceA - priceB;
                    case 'price-desc':
                        return priceB - priceA;
                    case 'rating-desc':
                        return (Number(b.rating) || 0) - (Number(a.rating) || 0);
                    default:
                        return (a.originalIndex ?? 0) - (b.originalIndex ?? 0);
                }
            });

            return { ...msg, products: sorted, selectedSort: selectedOption };
        });
    }
    handleCopyProductCode(event) {
        // منع فتح الـ Modal عند الضغط على زر النسخ من البطاقة
        event.stopPropagation();

        const code = event.currentTarget.dataset.code;

        if (code) {
            navigator.clipboard.writeText(code)
                .then(() => {
                    this.dispatchEvent(
                        new ShowToastEvent({
                            title: 'Success',
                            message: `Product Code (${code}) copied to clipboard!`,
                            variant: 'success'
                        })
                    );
                })
                .catch(err => {
                    console.error('Could not copy code: ', err);
                });
        }
    }
}