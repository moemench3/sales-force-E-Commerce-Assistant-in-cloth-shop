import { LightningElement, track } from 'lwc';

export default class RecipeOptimizer extends LightningElement {
    // -------------------------------------------------------------
    // 1. Reactive Properties & State
    // -------------------------------------------------------------
    newIngName = '';
    newIngUnit = 'Grams (g)';
    newIngCostPerTon = '';
    newIngFlavorProfile = '';
    searchTerm = '';
    selectedIngredientToAdd = '';

    newProductName = '';
    newProductDescription = '';
    newProductCategory = 'SPREAD';
    newProductWeight = '';
    newProductTargetMargin = '30';

    @track isNewProductModalOpen = false;
    @track isNewIngredientModalOpen = false;

    // Color palette for dynamically added ingredients
    colorPalette = ['#4caf50', '#2196f3', '#ff9800', '#e91e63', '#9c27b0', '#00bcd4', '#ff5722', 'hsl(239, 60%, 39%)'];

    // Categories and Units
    categoryOptions = [
        { label: 'SNACK', value: 'SNACK' },
        { label: 'SPREAD', value: 'SPREAD' },
        { label: 'SAUCE', value: 'SAUCE' }
    ];

    unitOptions = [
        { label: 'Grams (g)', value: 'Grams (g)' },
        { label: 'Kilograms (kg)', value: 'Kilograms (kg)' },
        { label: 'Liters (L)', value: 'Liters (L)' },
        { label: 'Milliliters (ml)', value: 'Milliliters (ml)' }
    ];

    // Master list of available ingredients for dropdown selection
    @track availableIngredients = [
        { id: 'ing_1', name: 'Cocoa Powder', costPerTon: 2500, unit: 'g' },
        { id: 'ing_2', name: 'Hazelnut Paste', costPerTon: 4000, unit: 'g' },
        { id: 'ing_3', name: 'Milk Powder', costPerTon: 1800, unit: 'g' },
        { id: 'ing_4', name: 'Palm Oil', costPerTon: 1100, unit: 'g' },
        { id: 'ing_5', name: 'Sea Salt', costPerTon: 300, unit: 'g' },
        { id: 'ing_6', name: 'Soy Lecithin', costPerTon: 1500, unit: 'g' },
        { id: 'ing_7', name: 'Sugar', costPerTon: 800, unit: 'g' },
        { id: 'ing_8', name: 'Vanilla Extract', costPerTon: 9500, unit: 'g' }
    ];

    // Product catalog for sidebar
    @track catalogProducts = [
        {
            id: 'p1',
            name: 'ChocoBar',
            category: 'SNACK',
            details: 'Not yet formulated',
            price: '$1.50',
            isSelected: false,
            cardClass: 'product-card',
            badgeClass: 'category-badge badge-snack'
        },
        {
            id: 'p2',
            name: 'Chocolate Spread',
            category: 'SPREAD',
            details: '100 g · 4 ingredients · 0.35% margin',
            price: '$0.21',
            isSelected: true,
            cardClass: 'product-card is-selected',
            badgeClass: 'category-badge badge-spread'
        },
        {
            id: 'p3',
            name: 'Hazelnut Cocoa Spread',
            category: 'SPREAD',
            details: '100 g · 5 ingredients · 0.32% margin',
            price: '$0.54',
            isSelected: false,
            cardClass: 'product-card',
            badgeClass: 'category-badge badge-spread'
        },
        {
            id: 'p4',
            name: 'KitKat chunky',
            category: 'SPREAD',
            details: 'Not yet formulated',
            price: '—',
            isSelected: false,
            cardClass: 'product-card',
            badgeClass: 'category-badge badge-spread'
        },
        {
            id: 'p5',
            name: 'Vanilla Dessert Sauce',
            category: 'SAUCE',
            details: 'Not yet formulated',
            price: '$3.00',
            isSelected: false,
            cardClass: 'product-card',
            badgeClass: 'category-badge badge-sauce'
        }
    ];

    // Active recipe ingredients (with initial weights and colors)
    @track ingredients = [
        { id: 'ing_1', name: 'Cocoa Powder', weight: 20, costPerTon: 2500, unit: 'g', color: '#f18c08' },
        { id: 'ing_2', name: 'Hazelnut Paste', weight: 15, costPerTon: 4000, unit: 'g', color: 'rgb(144, 247, 241)' },
        { id: 'ing_3', name: 'Milk Powder', weight: 15, costPerTon: 1800, unit: 'g', color: '#d61818' },
        { id: 'ing_7', name: 'Sugar', weight: 50, costPerTon: 800, unit: 'g', color: '#2d00f5' }
    ];

    // Ingredient insights cards
    @track ingredientInsights = [
        {
            id: 'ins1',
            name: 'Cocoa Powder',
            price: '$5,619.19 /mt',
            change: '-20.3%',
            isUp: false,
            badgeClass: 'trend-badge trend-down',
            badgeIcon: '↓',
            note: 'Price fell due to weaker West African crops and supply concerns.'
        },
        {
            id: 'ins2',
            name: 'Sugar',
            price: '$411.04 /mt',
            change: '+12.4%',
            isUp: true,
            badgeClass: 'trend-badge trend-up',
            badgeIcon: '↑',
            note: 'Supply disruptions and projected global deficit drove price up.'
        },
        {
            id: 'ins3',
            name: 'Palm Oil',
            price: '$1,106.47 /mt',
            change: '+5.1%',
            isUp: true,
            badgeClass: 'trend-badge trend-up',
            badgeIcon: '↑',
            note: 'Higher oil prices and biodiesel demand supported palm oil.'
        },
        {
            id: 'ins4',
            name: 'Milk Powder',
            price: '—',
            change: '—',
            isUp: false,
            badgeClass: 'trend-badge trend-neutral',
            badgeIcon: '',
            note: 'No clear current global price for milk powder found.'
        }
    ];

    // -------------------------------------------------------------
    // 2. Computed Properties (Getters)
    // -------------------------------------------------------------

    get filteredProducts() {
        if (!this.searchTerm) {
            return this.catalogProducts;
        }
        return this.catalogProducts.filter(item =>
            item.name.toLowerCase().includes(this.searchTerm.toLowerCase()) ||
            item.category.toLowerCase().includes(this.searchTerm.toLowerCase())
        );
    }

    get totalWeight() {
        return this.ingredients.reduce((acc, curr) => acc + Number(curr.weight || 0), 0);
    }

    get formattedIngredients() {
        const total = this.totalWeight || 1;
        return this.ingredients.map(item => {
            const pct = ((item.weight / total) * 100).toFixed(2);
            const pctInt = Math.round((item.weight / total) * 100);
            return {
                ...item,
                percentageFormatted: `${pct}%`,
                barPercentage: `${pctInt}%`,
                segmentStyle: `width: ${(item.weight / total) * 100}%; background-color: ${item.color || '#999'};`,
                legendSwatchStyle: `background-color: ${item.color || '#999'};`
            };
        });
    }

    get ingredientsSummaryText() {
        return `${this.ingredients.length} ingredients · total ${this.totalWeight}g`;
    }

    get estimatedCost() {
        // Dynamic cost estimation per batch based on costPerTon
        const totalCost = this.ingredients.reduce((acc, curr) => {
            const costPerGram = (curr.costPerTon || 0) / 1000000;
            return acc + (costPerGram * (curr.weight || 0));
        }, 0);
        return `$${totalCost.toFixed(4)}`;
    }

    get currentDistributionPrice() {
        return this.estimatedCost;
    }

    // -------------------------------------------------------------
    // 3. Event Handlers
    // -------------------------------------------------------------

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleProductSelect(event) {
        const selectedId = event.currentTarget.dataset.id;
        this.catalogProducts = this.catalogProducts.map(product => ({
            ...product,
            isSelected: product.id === selectedId,
            cardClass: product.id === selectedId ? 'product-card is-selected' : 'product-card'
        }));
    }

    handleWeightChange(event) {
        const ingId = event.target.dataset.id;
        const val = parseFloat(event.target.value) || 0;

        this.ingredients = this.ingredients.map(item => {
            if (item.id === ingId) {
                return { ...item, weight: val };
            }
            return item;
        });
    }

    handleIngredientSelectChange(event) {
        const selectedValue = event.target.value;

        if (selectedValue === 'ADD_NEW') {
            this.isNewIngredientModalOpen = true;
            event.target.value = '';
        } else if (selectedValue) {
            const selectedIngredient = this.availableIngredients.find(item => item.id === selectedValue);
            if (selectedIngredient) {
                this.addIngredientToRecipe(selectedIngredient);
            }
            event.target.value = '';
        }
    }

    handleAddRow() {
        if (this.availableIngredients.length > 0) {
            // Find an ingredient not yet present in the current recipe
            const availableToAdd = this.availableIngredients.find(
                item => !this.ingredients.some(ing => ing.id === item.id)
            );
            if (availableToAdd) {
                this.addIngredientToRecipe(availableToAdd);
            } else {
                // If all existing available ingredients are already added, fallback to first item
                this.addIngredientToRecipe(this.availableIngredients[0]);
            }
        }
    }

    addIngredientToRecipe(ingredient) {
        const exists = this.ingredients.some(item => item.id === ingredient.id);
        if (exists) {
            return; // Prevent duplicate rows for the same ingredient
        }

        const colorIndex = this.ingredients.length % this.colorPalette.length;
        const newRecipeItem = {
            ...ingredient,
            weight: 10, // Default starting weight in grams
            color: this.colorPalette[colorIndex]
        };

        this.ingredients = [...this.ingredients, newRecipeItem];
    }

    handleDeleteRow(event) {
        const ingId = event.currentTarget.dataset.id;
        this.ingredients = this.ingredients.filter(item => item.id !== ingId);
    }

    handleNewIngredientFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;

        if (field === 'name') this.newIngName = value;
        if (field === 'unit') this.newIngUnit = value;
        if (field === 'costPerTon') this.newIngCostPerTon = value;
        if (field === 'flavorProfile') this.newIngFlavorProfile = value;
    }

    closeNewIngredientModal() {
        this.isNewIngredientModalOpen = false;
        this.resetNewIngredientForm();
    }

    handleCreateAndAddIngredient() {
        if (!this.newIngName || !this.newIngName.trim()) {
            return;
        }

        const newIngredientObj = {
            id: `ing_${Date.now()}`,
            name: this.newIngName.trim(),
            unit: this.newIngUnit,
            costPerTon: parseFloat(this.newIngCostPerTon) || 0,
            flavorProfile: this.newIngFlavorProfile
        };

        // Add to global available ingredients list
        this.availableIngredients = [...this.availableIngredients, newIngredientObj];

        // Add directly into active recipe
        this.addIngredientToRecipe(newIngredientObj);

        // Close modal & reset form
        this.closeNewIngredientModal();
    }

    resetNewIngredientForm() {
        this.newIngName = '';
        this.newIngUnit = 'Grams (g)';
        this.newIngCostPerTon = '';
        this.newIngFlavorProfile = '';
    }

    // Modal - Product Catalog
    handleNewProduct() {
        this.isNewProductModalOpen = true;
    }

    closeNewProductModal() {
        this.isNewProductModalOpen = false;
        this.newProductName = '';
        this.newProductCategory = '';
        this.newProductWeight = null;
        this.newProductTargetMargin = null;
    }

    handleNewProductFieldChange(event) {
        const field = event.target.dataset.field;
        const value = event.target.value;

        if (field === 'name') this.newProductName = value;
        if (field === 'category') this.newProductCategory = value;
        if (field === 'weight') this.newProductWeight = value;
        if (field === 'targetMargin') this.newProductTargetMargin = value;
    }

    handleSaveNewProduct() {
        if (!this.newProductName || !this.newProductName.trim()) {
            return;
        }

        const categoryLower = (this.newProductCategory || 'spread').toLowerCase();
        const weightText = this.newProductWeight ? `${this.newProductWeight} g` : 'Not yet formulated';
        const marginText = this.newProductTargetMargin ? `${this.newProductTargetMargin}% margin` : '';
        const detailsText = `${weightText} ${marginText ? '· ' + marginText : ''}`;

        const newProd = {
            id: `p_${Date.now()}`,
            name: this.newProductName.trim(),
            category: this.newProductCategory,
            description: this.newProductDescription,
            details: detailsText,
            price: '—',
            isSelected: false,
            cardClass: 'product-card',
            badgeClass: `category-badge badge-${categoryLower}`
        };

        this.catalogProducts = [newProd, ...this.catalogProducts];
        this.closeNewProductModal();
    }

    resetNewProductForm() {
        this.newProductName = '';
        this.newProductDescription = '';
        this.newProductWeight = '';
        this.newProductCategory = 'SPREAD';
        this.newProductTargetMargin = '30';
    }

    handleOptimizeRecipe() {
        console.log('Optimizing recipe parameters...');
    }

    handleRefreshMarket() {
        console.log('Refreshing market trends...');
    }

    handleClearForm() {
        this.ingredients = [];
        this.selectedIngredientToAdd = '';
    }

    handleSaveRecipe() {
        console.log('Saving recipe logic / Apex call here...', JSON.stringify(this.ingredients));
    }
}