import { CloudFrontRequestEvent } from "aws-lambda";

const isPost = /^\/post(.+)/;
const hasExtension = /(.+)\.[a-zA-Z0-9]{2,5}$/;

export const handler = async (event: CloudFrontRequestEvent, context: unknown) => {
    const request = event.Records[0].cf.request;
    const url: string = request.uri;

    // if it's a post request and has not extension, add .html
    if (url && url.match(isPost) && !url.match(hasExtension)) {
        request.uri = `${url}.html`;
    }

    return request;
}
