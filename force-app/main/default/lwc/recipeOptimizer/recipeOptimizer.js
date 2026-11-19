import { LightningElement, track } from 'lwc';
import calculateCost from '@salesforce/apex/RecipeOptimizerController.calculateCost';
import createIngredient from '@salesforce/apex/RecipeOptimizerController.createIngredient';
import createProduct from '@salesforce/apex/RecipeOptimizerController.createProduct';
import getIngredients from '@salesforce/apex/RecipeOptimizerController.getIngredients';
import getProducts from '@salesforce/apex/RecipeOptimizerController.getProducts';
import getRecipe from '@salesforce/apex/RecipeOptimizerController.getRecipe';
import updateRecipe from '@salesforce/apex/RecipeOptimizerController.updateRecipe';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import {
    getIngredientPrices,
    getIngredientRecommendations,
    getPriceHistory,
    getRandomCatalogCards,
    buildPriceProjectionPayload,
    projectRecipePrices
} from './ingredientAiService';

const ROTATION_INTERVAL_MS = 10000;
const CARD_COUNT = 5;
const SIGNIFICANT_AI_DELTA = 5;
const INGREDIENT_COLORS = ['#b98027', '#e6c98f', '#8aa25f', '#507086', '#a65d3f', '#7a8b6f'];

export default class RecipeOptimizer extends LightningElement {
    @track products = [];
    @track ingredients = [];
    @track recipeLines = [];
    @track ingredientTableRows = [];
    @track filteredProducts = [];
    @track displayCards = [];
    @track summary = { totalCost: 0, totalQuantity: 0, estimatedMargin: 0 };
    @track priceHistoryPoints = [];
    @track oldDistributionNewPrice = null;
    @track newDistributionNewPrice = null;

    selectedProductId = '';
    selectedProductMeta = {};
    productSearchTerm = '';
    ingredientSearchTerm = '';
    ingredientToAdd = '';
    isSaving = false;
    isAiLoading = false;
    isInsightsLoading = false;
    isHistoryLoading = false;
    isMoreInfoOpen = false;
    moreInfoTitle = '';
    rotationMode = false;
    isNewProductOpen = false;
    isNewIngredientOpen = false;
    isCreatingIngredient = false;
    lockedCardIds = new Set();

    newIngredient = {
        name: '',
        unit: 'g',
        defaultCost: null,
        flavorProfile: ''
    };

    unitOptions = [
        { label: 'Grams (g)', value: 'g' },
        { label: 'Kilograms (kg)', value: 'kg' },
        { label: 'Liters (L)', value: 'L' },
        { label: 'Milliliters (mL)', value: 'mL' }
    ];

    rotationTimer;
    productStatsCache = {};

    newProduct = {
        name: '',
        description: '',
        category: 'Spread',
        totalWeight: null,
        targetMargin: 30
    };

    categoryOptions = [
        { label: 'Spread', value: 'Spread' },
        { label: 'Sauce', value: 'Sauce' },
        { label: 'Snack', value: 'Snack' }
    ];

    get hasSelectedProduct() {
        return !!this.selectedProductId;
    }

    get selectedProductName() {
        return this.selectedProductMeta?.name || '';
    }

    get hasFilteredProducts() {
        return this.filteredProducts.length > 0;
    }

    get hasIngredientRows() {
        return this.ingredientTableRows.length > 0;
    }

    get isOptimizeDisabled() {
        return (
            this.isAiLoading ||
            this.isInsightsLoading ||
            !this.recipeLines.length ||
            !this.displayCards.length
        );
    }

    get gridLoadingHostClass() {
        return this.isAiLoading ? 'loading-host is-busy' : 'loading-host';
    }

    get insightsLoadingHostClass() {
        return this.isInsightsLoading ? 'loading-host is-busy insights-loading-host' : 'loading-host insights-loading-host';
    }

    get oldDistributionNewPriceLabel() {
        return this.formatCurrency(this.oldDistributionNewPrice, 4);
    }

    get newDistributionNewPriceLabel() {
        return this.formatCurrency(this.newDistributionNewPrice, 4);
    }

    get optimizedPriceRibbonLabel() {
        return this.formatCurrency(this.newDistributionNewPrice, 4);
    }

    get hasFromPrice() {
        return this.newDistributionNewPrice != null && this.oldDistributionNewPrice != null;
    }

    get totalWeightRibbonLabel() {
        const weight = this.effectiveTotalWeight;
        return weight != null ? `${weight} g` : '—';
    }

    get estimatedCostLabel() {
        const cost = this.summary?.totalCost;
        if (cost == null || cost === '') {
            return '—';
        }
        return this.formatCurrency(cost, 2);
    }

    get targetMarginRibbonLabel() {
        const margin = this.selectedProductMeta?.targetMargin;
        return margin != null ? `${margin}%` : '—';
    }

    get formulationTitle() {
        return `${this.selectedProductName} — formulation`;
    }

    get formulationBreadcrumb() {
        return `Products / ${this.selectedProductName} / Editing recipe`;
    }

    get compositionSubtitle() {
        const count = this.ingredientTableRows.length;
        const noun = count === 1 ? 'ingredient' : 'ingredients';
        return `${count} ${noun} · sums to 100%`;
    }

    get distributionSegments() {
        return this.ingredientTableRows.map((row, index) => {
            const pct = Number(String(row.percentageLabel).replace('%', '')) || 0;
            const color = INGREDIENT_COLORS[index % INGREDIENT_COLORS.length];
            return {
                key: row.clientKey || `${row.ingredientId}-${index}`,
                name: row.ingredientName,
                percentLabel: `${Math.round(pct)}%`,
                showLabel: pct >= 8,
                title: `${row.ingredientName} ${row.percentageLabel}`,
                style: `width:${pct}%;background:${color}`,
                swatchStyle: `background:${color}`
            };
        });
    }

    get effectiveTotalWeight() {
        const configured = Number(this.selectedProductMeta?.totalWeight);
        const calculated = this.recipeLines.reduce((sum, row) => sum + (Number(row.quantity) || 0), 0);
        if (configured > 0) {
            return configured;
        }
        return Number(calculated.toFixed(2));
    }

    get insightsSubtitle() {
        if (!this.hasSelectedProduct) {
            return 'Select a product to view ingredient insights.';
        }
        if (this.rotationMode) {
            return 'Discovery mode: cards rotate every 10 seconds. Click a card to lock it.';
        }
        return 'Linked to this recipe.';
    }

    get filteredIngredientOptions() {
        const term = (this.ingredientSearchTerm || '').trim().toLowerCase();
        const usedIds = new Set(this.recipeLines.map((line) => line.ingredientId));
        const options = this.ingredients
            .filter((row) => !usedIds.has(row.id))
            .filter((row) => !term || row.name.toLowerCase().includes(term))
            .map((row) => ({ label: row.name, value: row.id }));
        return [{ label: '+ Add new ingredient...', value: '__NEW__' }, ...options];
    }

    async connectedCallback() {
        await this.bootstrap();
    }

    disconnectedCallback() {
        this.clearRotationTimer();
    }

    async bootstrap() {
        try {
            const [products, ingredients] = await Promise.all([getProducts(), getIngredients()]);
            this.products = (products || []).map((row) => this.decorateProductRow(row));
            this.ingredients = ingredients || [];
            this.applyProductFilter();
        } catch (error) {
            this.showError('Unable to load data', error);
        }
    }

    decorateProductRow(row) {
        const stats = this.productStatsCache[row.id] || {};
        const isSelected = row.id === this.selectedProductId;
        const hasFormula = stats.ingredientCount != null && stats.ingredientCount > 0;
        const category = (row.category || '').toLowerCase();
        let detailsLabel = 'Not yet formulated';
        if (hasFormula) {
            const weight = stats.totalWeight != null ? `${stats.totalWeight} g` : '—';
            const count = `${stats.ingredientCount} ingredient${stats.ingredientCount === 1 ? '' : 's'}`;
            const margin = row.targetMargin != null ? `${row.targetMargin}% margin` : 'no margin';
            detailsLabel = `${weight} · ${count} · ${margin}`;
        }
        return {
            ...row,
            categoryLabel: row.category || '—',
            categoryBadgeClass: `category-badge badge-${category || 'default'}`,
            targetMarginLabel: row.targetMargin != null ? `${row.targetMargin}%` : '—',
            lastPriceLabel: this.formatMoney(row.lastPrice),
            lastPriceDisplay: this.formatCurrency(row.lastPrice, 2),
            totalWeightLabel: stats.totalWeight != null ? stats.totalWeight : '—',
            ingredientCount: stats.ingredientCount != null ? stats.ingredientCount : '—',
            detailsLabel,
            cardClass: isSelected ? 'product-card is-selected' : 'product-card'
        };
    }

    applyProductFilter() {
        const term = (this.productSearchTerm || '').trim().toLowerCase();
        const filtered = this.products.filter((row) => !term || row.name.toLowerCase().includes(term));
        this.filteredProducts = filtered.map((row) => ({
            ...row,
            cardClass: row.id === this.selectedProductId ? 'product-card is-selected' : 'product-card'
        }));
    }

    async selectProduct(productId) {
        this.selectedProductId = productId;
        const product = this.products.find((p) => p.id === productId);
        this.selectedProductMeta = {
            id: productId,
            name: product?.name,
            category: product?.category,
            totalWeight: this.productStatsCache[productId]?.configuredTotalWeight || null,
            targetMargin: product?.targetMargin
        };
        this.resetPriceProjection();
        this.applyProductFilter();
        await this.loadRecipeForSelectedProduct();
    }

    async loadRecipeForSelectedProduct() {
        if (!this.selectedProductId) {
            return;
        }

        try {
            const [lines, summary] = await Promise.all([
                getRecipe({ productId: this.selectedProductId }),
                calculateCost({ productId: this.selectedProductId })
            ]);

            this.recipeLines = (lines || []).map((line, index) => ({
                id: line.id,
                ingredientId: line.ingredientId,
                ingredientName: line.ingredientName,
                quantity: line.quantity || 0,
                unit: line.unit || 'kg',
                clientKey: `${line.id || 'new'}-${index}`
            }));
            this.summary = summary || this.summary;

            const totalWeight = this.recipeLines.reduce((sum, row) => sum + (Number(row.quantity) || 0), 0);
            this.productStatsCache[this.selectedProductId] = {
                ingredientCount: this.recipeLines.length,
                totalWeight: Number(totalWeight.toFixed(2)),
                configuredTotalWeight: this.selectedProductMeta.totalWeight
            };
            this.products = this.products.map((row) => this.decorateProductRow(row));
            this.applyProductFilter();

            this.rotationMode = this.recipeLines.length === 0;
            await this.runMarketScout();
        } catch (error) {
            this.showError('Unable to load recipe', error);
        }
    }

    buildIngredientTableRows(aiRecommendations = []) {
        const aiByIngredientId = new Map();
        const aiByIngredientName = new Map();
        aiRecommendations.forEach((item) => {
            if (item.ingredientId) {
                aiByIngredientId.set(item.ingredientId, item);
            }
            if (item.ingredientName) {
                aiByIngredientName.set(item.ingredientName.toLowerCase(), item);
            }
        });
        const total = this.effectiveTotalWeight;

        this.ingredientTableRows = this.recipeLines.map((line, index) => {
            const weight = Number(line.quantity) || 0;
            const percentage = total > 0 ? (weight / total) * 100 : 0;
            const ai =
                aiByIngredientId.get(line.ingredientId) ||
                aiByIngredientName.get((line.ingredientName || '').toLowerCase()) ||
                {};
            const aiPct = ai.aiPercentageSuggestion != null ? Number(ai.aiPercentageSuggestion) : null;
            const aiWeight = ai.aiWeightSuggestion != null ? Number(ai.aiWeightSuggestion) : null;
            const delta = aiPct != null ? Math.abs(aiPct - percentage) : 0;
            const hasSignificantDelta = delta >= SIGNIFICANT_AI_DELTA;
            const color = INGREDIENT_COLORS[index % INGREDIENT_COLORS.length];
            const hasAiBadge = aiWeight != null && !Number.isNaN(aiWeight);
            const weightDelta = hasAiBadge ? Number((aiWeight - weight).toFixed(2)) : 0;
            const arrow = weightDelta < 0 ? '↓' : weightDelta > 0 ? '↑' : '→';
            const deltaLabel = `${weightDelta > 0 ? '+' : ''}${weightDelta}`;

            return {
                ...line,
                weight,
                percentageLabel: `${percentage.toFixed(2)}%`,
                aiWeightSuggestion: hasAiBadge ? aiWeight : '—',
                aiPercentageSuggestion: aiPct != null ? `${aiPct.toFixed(2)}%` : '—',
                aiComment: ai.aiComment || '—',
                hasAiBadge,
                aiBadgeLabel: hasAiBadge ? `AI ${aiWeight} g ${arrow} ${deltaLabel}` : '—',
                aiBadgeClass: weightDelta < 0 ? 'ai-badge ai-down' : 'ai-badge ai-up',
                swatchStyle: `background:${color}`,
                rowClass: hasSignificantDelta ? 'row-ai-highlight' : ''
            };
        });
    }

    getIngredientRowsForAi() {
        return this.recipeLines.map((line) => ({
            ingredientId: line.ingredientId,
            ingredientName: line.ingredientName,
            weight: line.quantity,
            unit: line.unit || 'kg'
        }));
    }

    getProductMetaForAi() {
        return {
            id: this.selectedProductId,
            name: this.selectedProductName,
            targetMargin: this.selectedProductMeta?.targetMargin
        };
    }

    /**
     * Agent 1 only: Commodity_Market_Scout.
     * Fills insight cards and keeps AI grid columns empty until Optimize Recipe is clicked.
     */
    async runMarketScout() {
        this.clearRotationTimer();

        if (!this.selectedProductId) {
            this.displayCards = [];
            this.ingredientTableRows = [];
            this.resetPriceProjection();
            return;
        }

        if (this.rotationMode) {
            this.renderRotatingCards();
            this.rotationTimer = setInterval(() => {
                this.renderRotatingCards();
            }, ROTATION_INTERVAL_MS);
            this.ingredientTableRows = [];
            this.resetPriceProjection();
            return;
        }

        if (!this.recipeLines.length) {
            this.displayCards = [];
            this.ingredientTableRows = [];
            this.resetPriceProjection();
            return;
        }

        this.isInsightsLoading = true;
        this.buildIngredientTableRows([]);

        try {
            const { commodityCards } = await getIngredientPrices(this.getIngredientRowsForAi());
            this.displayCards = (commodityCards || []).map((card) => ({
                ...card,
                locked: this.lockedCardIds.has(card.cardId)
            }));
            // Display projected mix prices only. Do not write Last_Price__c on select or market refresh.
            await this.refreshPriceProjection(false);
        } catch (error) {
            this.showError('Unable to load market prices', error);
        } finally {
            this.isInsightsLoading = false;
        }
    }

    /**
     * Agent 2 only: Ingredient_Optimization_AI, using current recipe + scout cards.
     */
    async runIngredientOptimization() {
        if (!this.recipeLines.length) {
            this.showToast('Optimize Recipe', 'Add ingredients before running optimization.', 'warning');
            return;
        }
        if (!this.displayCards.length) {
            this.showToast(
                'Optimize Recipe',
                'Load market prices first (Refresh Market), then run optimization.',
                'warning'
            );
            return;
        }

        this.isAiLoading = true;
        try {
            const recommendations = await getIngredientRecommendations(
                this.getIngredientRowsForAi(),
                this.effectiveTotalWeight,
                this.getProductMetaForAi(),
                this.displayCards
            );
            this.buildIngredientTableRows(recommendations || []);
            await this.refreshPriceProjection(true);
        } catch (error) {
            this.showError('Unable to optimize recipe', error);
        } finally {
            this.isAiLoading = false;
        }
    }

    async refreshInsightsPanel() {
        if (this.rotationMode && this.selectedProductId) {
            this.renderRotatingCards();
            return;
        }
        await this.runMarketScout();
    }

    renderRotatingCards() {
        const lockedCards = this.displayCards.filter((card) => this.lockedCardIds.has(card.cardId));
        const unlockedSlots = CARD_COUNT - lockedCards.length;
        const randomCards = getRandomCatalogCards(unlockedSlots, [...this.lockedCardIds]);
        const refreshed = [...lockedCards, ...randomCards.map((card) => ({ ...card, locked: false }))].slice(0, CARD_COUNT);
        this.displayCards = refreshed;
    }

    clearRotationTimer() {
        if (this.rotationTimer) {
            clearInterval(this.rotationTimer);
            this.rotationTimer = null;
        }
    }

    handleNewProductChange(event) {
        const field = event.currentTarget.dataset.field;
        const value = event.detail ? event.detail.value : event.target.value;
        const numericFields = new Set(['totalWeight', 'targetMargin']);
        this.newProduct = {
            ...this.newProduct,
            [field]: numericFields.has(field) ? (value === '' || value == null ? null : Number(value)) : value
        };
    }

    handleClearProductForm() {
        this.newProduct = {
            name: '',
            description: '',
            category: 'Spread',
            totalWeight: null,
            targetMargin: 30
        };
    }

    handleToggleNewProduct() {
        this.isNewProductOpen = !this.isNewProductOpen;
    }

    handleProductSearch(event) {
        this.productSearchTerm = event.target.value;
        this.applyProductFilter();
    }

    handleIngredientSearch(event) {
        this.ingredientSearchTerm = event.target.value;
    }

    handleProductRowSelect(event) {
        const productId = event.currentTarget.dataset.id;
        if (productId) {
            this.selectProduct(productId);
        }
    }

    handleIngredientToAddChange(event) {
        const val = event.detail.value;
        if (val === '__NEW__') {
            this.ingredientToAdd = '';
            this.isNewIngredientOpen = true;
            return;
        }
        this.ingredientToAdd = val;
    }

    handleAddIngredientFromCatalog() {
        if (!this.ingredientToAdd) {
            this.showToast('Add Ingredient', 'Select an ingredient first.', 'warning');
            return;
        }

        const ingredient = this.ingredients.find((row) => row.id === this.ingredientToAdd);
        if (!ingredient) {
            return;
        }

        this.recipeLines = [
            ...this.recipeLines,
            {
                ingredientId: ingredient.id,
                ingredientName: ingredient.name,
                quantity: 0,
                unit: ingredient.unit || 'kg',
                clientKey: `${ingredient.id}-${Date.now()}`
            }
        ];
        this.ingredientToAdd = '';
        this.rotationMode = false;
        this.runMarketScout();
    }

    handleNewIngredientChange(event) {
        const field = event.currentTarget.dataset.field;
        this.newIngredient = { ...this.newIngredient, [field]: event.detail.value ?? event.target.value };
    }

    handleCloseNewIngredient() {
        this.isNewIngredientOpen = false;
        this.resetNewIngredientForm();
    }

    resetNewIngredientForm() {
        this.newIngredient = { name: '', unit: 'g', defaultCost: null, flavorProfile: '' };
    }

    async handleCreateIngredient() {
        if (!this.newIngredient.name || !this.newIngredient.name.trim()) {
            this.showToast('New Ingredient', 'Ingredient name is required.', 'warning');
            return;
        }
        this.isCreatingIngredient = true;
        try {
            const newId = await createIngredient({
                name: this.newIngredient.name.trim(),
                unit: this.newIngredient.unit || 'g',
                defaultCost: this.newIngredient.defaultCost ? Number(this.newIngredient.defaultCost) : null,
                flavorProfile: this.newIngredient.flavorProfile || null
            });
            const newRow = {
                id: newId,
                name: this.newIngredient.name.trim(),
                unit: this.newIngredient.unit || 'g',
                defaultCost: this.newIngredient.defaultCost ? Number(this.newIngredient.defaultCost) : null,
                flavorProfile: this.newIngredient.flavorProfile || ''
            };
            this.ingredients = [...this.ingredients, newRow];
            this.recipeLines = [
                ...this.recipeLines,
                {
                    ingredientId: newId,
                    ingredientName: newRow.name,
                    quantity: 0,
                    unit: newRow.unit,
                    clientKey: `${newId}-${Date.now()}`
                }
            ];
            this.isNewIngredientOpen = false;
            this.resetNewIngredientForm();
            this.rotationMode = false;
            this.runMarketScout();
            this.showToast('Ingredient Created', `${newRow.name} added to recipe.`, 'success');
        } catch (error) {
            this.showError('Create Ingredient Failed', error);
        } finally {
            this.isCreatingIngredient = false;
        }
    }

    handleWeightChange(event) {
        const index = Number(event.currentTarget.dataset.index);
        const raw = event.detail ? event.detail.value : event.target.value;
        const value = Number(raw) || 0;
        this.recipeLines = this.recipeLines.map((line, idx) => (idx === index ? { ...line, quantity: value } : line));

        const cachedAi = this.ingredientTableRows.map((row) => ({
            ingredientId: row.ingredientId,
            aiWeightSuggestion:
                row.aiWeightSuggestion === '—' ? null : Number(row.aiWeightSuggestion),
            aiPercentageSuggestion:
                row.aiPercentageSuggestion === '—' ? null : Number(String(row.aiPercentageSuggestion).replace('%', '')),
            aiComment: row.aiComment === '—' ? '' : row.aiComment
        }));
        this.buildIngredientTableRows(cachedAi);
        this.refreshPriceProjection(false);
    }

    handleRemoveIngredient(event) {
        const index = Number(event.currentTarget.dataset.index);
        this.recipeLines = this.recipeLines.filter((_, idx) => idx !== index);
        if (this.recipeLines.length === 0) {
            this.rotationMode = true;
        }
        this.runMarketScout();
    }

    async handleCreateProduct() {
        if (!this.newProduct.name?.trim()) {
            this.showToast('Missing Product Name', 'Enter a product name first.', 'warning');
            return;
        }

        this.isSaving = true;
        try {
            const productId = await createProduct({
                name: this.newProduct.name.trim(),
                category: this.newProduct.category,
                targetMargin: this.newProduct.targetMargin
            });

            this.productStatsCache[productId] = {
                ingredientCount: 0,
                totalWeight: this.newProduct.totalWeight || 0,
                configuredTotalWeight: this.newProduct.totalWeight
            };

            await this.bootstrap();
            this.selectedProductMeta = {
                id: productId,
                name: this.newProduct.name.trim(),
                category: this.newProduct.category,
                totalWeight: this.newProduct.totalWeight,
                description: this.newProduct.description
            };
            this.selectedProductId = productId;
            this.recipeLines = [];
            this.rotationMode = true;
            this.lockedCardIds = new Set();
            this.applyProductFilter();
            await this.runMarketScout();
            this.handleClearProductForm();
            this.isNewProductOpen = false;
            this.showToast('Success', 'Product created. Add ingredients below.', 'success');
        } catch (error) {
            this.showError('Unable to create product', error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleSave() {
        if (!this.selectedProductId) {
            this.showToast('Missing Product', 'Select a product first.', 'warning');
            return;
        }

        this.isSaving = true;
        try {
            const payload = this.recipeLines
                .filter((line) => line.ingredientId)
                .map((line) => ({
                    id: line.id,
                    ingredientId: line.ingredientId,
                    quantity: line.quantity,
                    unit: line.unit
                }));

            await updateRecipe({ productId: this.selectedProductId, lines: payload });
            await this.loadRecipeForSelectedProduct();
            this.showToast('Success', 'Recipe saved.', 'success');
        } catch (error) {
            this.showError('Unable to save recipe', error);
        } finally {
            this.isSaving = false;
        }
    }

    async handleRefreshAi() {
        await this.runMarketScout();
    }

    async handleOptimizeRecipe() {
        await this.runIngredientOptimization();
    }

    handleCardSelect(event) {
        const cardId = event.detail.cardId;
        if (!cardId) {
            return;
        }
        this.lockedCardIds.add(cardId);
        this.displayCards = this.displayCards.map((card) =>
            card.cardId === cardId ? { ...card, locked: true } : card
        );
    }

    async handleMoreInfo(event) {
        const card = event.detail.card;
        this.isMoreInfoOpen = true;
        this.moreInfoTitle = `${card.name || card.ingredientName} - Price History`;
        this.isHistoryLoading = true;
        try {
            const history = await getPriceHistory(card.name || card.ingredientName);
            this.priceHistoryPoints = history.points || [];
        } finally {
            this.isHistoryLoading = false;
        }
    }

    handleCloseMoreInfo() {
        this.isMoreInfoOpen = false;
        this.priceHistoryPoints = [];
    }

    showError(title, error) {
        let message = error?.body?.message || error?.body?.pageErrors?.[0]?.message || error?.message;
        if (!message && error?.body?.fieldErrors) {
            message = JSON.stringify(error.body.fieldErrors);
        }
        this.showToast(title, message || 'Unknown error', 'error');
    }

    resetPriceProjection() {
        this.oldDistributionNewPrice = null;
        this.newDistributionNewPrice = null;
    }

    async refreshPriceProjection(persistLastPrice = false) {
        if (!this.recipeLines.length || !this.displayCards.length) {
            this.resetPriceProjection();
            return;
        }

        const payload = buildPriceProjectionPayload(
            this.getIngredientRowsForAi(),
            this.getProductMetaForAi(),
            this.displayCards,
            this.ingredientTableRows,
            persistLastPrice
        );

        try {
            const result = await projectRecipePrices(payload);
            this.oldDistributionNewPrice =
                result?.oldDistributionNewPrice != null ? Number(result.oldDistributionNewPrice) : null;
            this.newDistributionNewPrice =
                result?.newDistributionNewPrice != null ? Number(result.newDistributionNewPrice) : null;
            if (persistLastPrice && result?.lastPrice != null) {
                this.applyLastPriceToGrid(result.lastPrice);
            }
        } catch (error) {
            this.showError('Unable to project prices', error);
        }
    }

    applyLastPriceToGrid(lastPrice) {
        this.products = this.products.map((row) =>
            row.id === this.selectedProductId ? this.decorateProductRow({ ...row, lastPrice }) : row
        );
        this.applyProductFilter();
    }

    formatMoney(value, scale = 2) {
        if (value == null || value === '' || Number.isNaN(Number(value))) {
            return '—';
        }
        return Number(value).toFixed(scale);
    }

    formatCurrency(value, scale = 2) {
        if (value == null || value === '' || Number.isNaN(Number(value))) {
            return '—';
        }
        return `$${Number(value).toFixed(scale)}`;
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}