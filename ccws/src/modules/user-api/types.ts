enum Comparator {
    eq = 'eq',
    neq = 'neq',
    lt = 'lt',
    lte = 'lte',
    gt = 'gt',
	gte = 'gte'
}

interface SimpleExpression {
	attribute: string;
	comparator: Comparator;
	value: string;
}

interface AndExpression {
	and: Expression[];
}

interface OrExpression {
	or: Expression[];
}

export type Expression = SimpleExpression | AndExpression | OrExpression;


export type UserId = {
    id: string
}

export type UsersIdList = {
    users: UserId[]
}


export type UserAttributes = {
    id: string,
    name: string,
    isGroup: boolean,
    avatar: string,
    language: string,
    captions: boolean,
    subtitle: boolean,
    signLanguageWindow: boolean,
    audioDescription: boolean,
    dialogEnhancement: boolean
} | string